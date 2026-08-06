package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"strings"
	"sync"
	"time"
)

const (
	dnsHeaderLen   = 12
	typeAAAA       = 28
	udpWorkerCount = 128
	udpQueueSize   = 1024
	tcpConnLimit   = 128
)

type udpRequest struct {
	query []byte
	addr  net.Addr
}

type server struct {
	listen        string
	upstreams     []string
	timeout       time.Duration
	domains       []string
	tcpSlots      chan struct{}
	filterAllAAAA bool
}

func main() {
	listen := flag.String("listen", "127.0.0.1:1053", "UDP/TCP listen address")
	upstream := flag.String("upstream", "223.5.5.5:53,119.29.29.29:53", "comma-separated upstream DNS servers")
	domainFile := flag.String("domains", "", "domain suffix file")
	timeout := flag.Duration("timeout", 5*time.Second, "upstream timeout")
	filterAllAAAA := flag.Bool("filter-all-aaaa", false, "return NODATA for every AAAA query")
	validateConfig := flag.String("validate-config", "", "validate a module JSON config file and exit")
	flag.Parse()
	if *validateConfig != "" {
		if err := validateModuleConfig(*validateConfig); err != nil {
			log.Fatalf("invalid config: %v", err)
		}
		return
	}

	domains, err := loadDomains(*domainFile)
	if err != nil && !*filterAllAAAA {
		log.Fatalf("load domains: %v", err)
	}
	if len(domains) == 0 && !*filterAllAAAA {
		log.Fatal("no IPv4-only domains configured")
	}

	upstreams := parseUpstreams(*upstream)
	if len(upstreams) == 0 {
		log.Fatal("no upstream DNS servers configured")
	}

	s := &server{listen: *listen, upstreams: upstreams, timeout: *timeout, domains: domains, tcpSlots: make(chan struct{}, tcpConnLimit), filterAllAAAA: *filterAllAAAA}
	udpConn, err := net.ListenPacket("udp4", s.listen)
	if err != nil {
		log.Fatalf("listen UDP %s: %v", s.listen, err)
	}
	tcpLn, err := net.Listen("tcp4", s.listen)
	if err != nil {
		udpConn.Close()
		log.Fatalf("listen TCP %s: %v", s.listen, err)
	}
	log.Printf("IPv4-only DNS filter listening on %s, upstreams %s, domains %d, filter_all_aaaa=%t", s.listen, strings.Join(s.upstreams, ","), len(s.domains), s.filterAllAAAA)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); s.serveUDP(udpConn) }()
	go func() { defer wg.Done(); s.serveTCP(tcpLn) }()
	wg.Wait()
}

type moduleConfig struct {
	ProxyType   string `json:"proxy_type"`
	ListenPort  int    `json:"listen_port"`
	WebUIPort   int    `json:"webui_port"`
	Transparent *struct {
		IPv6Enabled *bool `json:"ipv6_enabled"`
	} `json:"transparent"`
	Upstream *struct {
		Enabled bool   `json:"enabled"`
		Addr    string `json:"addr"`
		Port    int    `json:"port"`
		Route   string `json:"route"`
	} `json:"upstream"`
	Routing *struct {
		DirectUIDs []int `json:"direct_uids"`
	} `json:"routing"`
	Advanced *struct {
		MultiListen []int `json:"multi_listen"`
	} `json:"advanced"`
}

func validateModuleConfig(path string) error {
	data, err := os.ReadFile(path)
	if err != nil {
		return err
	}
	if len(data) == 0 || len(data) > 65536 {
		return fmt.Errorf("config size must be between 1 and 65536 bytes")
	}
	var cfg moduleConfig
	decoder := json.NewDecoder(bytes.NewReader(data))
	if err := decoder.Decode(&cfg); err != nil {
		return err
	}
	var extra any
	if err := decoder.Decode(&extra); err != io.EOF {
		if err == nil {
			return errors.New("multiple JSON values")
		}
		return err
	}
	if cfg.ProxyType != "redirect" && cfg.ProxyType != "socks5" {
		return errors.New("proxy_type must be redirect or socks5")
	}
	if cfg.ListenPort < 1 || cfg.ListenPort > 65535 {
		return errors.New("listen_port is out of range")
	}
	if cfg.WebUIPort != 0 && (cfg.WebUIPort < 1 || cfg.WebUIPort > 65535) {
		return errors.New("webui_port is out of range")
	}
	if cfg.Upstream != nil {
		if cfg.Upstream.Enabled && (cfg.Upstream.Addr == "" || cfg.Upstream.Port < 1 || cfg.Upstream.Port > 65535) {
			return errors.New("enabled upstream requires an address and valid port")
		}
		switch cfg.Upstream.Route {
		case "", "ws", "wss":
		default:
			return errors.New("upstream route must be empty, ws, or wss")
		}
	}
	if cfg.Advanced != nil {
		for _, port := range cfg.Advanced.MultiListen {
			if port < 1 || port > 65535 {
				return errors.New("advanced multi_listen contains an invalid port")
			}
		}
	}
	if cfg.Routing != nil {
		for _, uid := range cfg.Routing.DirectUIDs {
			if uid < 0 {
				return errors.New("routing direct_uids contains a negative UID")
			}
		}
	}
	return nil
}

func parseUpstreams(value string) []string {
	seen := make(map[string]bool)
	var upstreams []string
	for _, item := range strings.Split(value, ",") {
		item = strings.TrimSpace(item)
		if item == "" {
			continue
		}
		if _, _, err := net.SplitHostPort(item); err != nil {
			item = net.JoinHostPort(item, "53")
		}
		if !seen[item] {
			seen[item] = true
			upstreams = append(upstreams, item)
		}
	}
	return upstreams
}

func loadDomains(path string) ([]string, error) {
	if path == "" {
		return nil, errors.New("domain file is required")
	}
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	seen := make(map[string]bool)
	var domains []string
	for _, line := range strings.Split(string(data), "\n") {
		line = strings.TrimSpace(strings.ToLower(line))
		if i := strings.IndexByte(line, '#'); i >= 0 {
			line = strings.TrimSpace(line[:i])
		}
		line = strings.TrimPrefix(line, ".")
		line = strings.TrimSuffix(line, ".")
		if line == "" || seen[line] {
			continue
		}
		seen[line] = true
		domains = append(domains, line)
	}
	return domains, nil
}

func (s *server) serveUDP(conn net.PacketConn) {
	defer conn.Close()
	requests := make(chan udpRequest, udpQueueSize)
	for i := 0; i < udpWorkerCount; i++ {
		go s.udpWorker(conn, requests)
	}

	buf := make([]byte, 65535)
	for {
		n, addr, err := conn.ReadFrom(buf)
		if err != nil {
			log.Printf("UDP read: %v", err)
			return
		}
		request := udpRequest{query: append([]byte(nil), buf[:n]...), addr: addr}
		select {
		case requests <- request:
		default:
			response := serverFailure(request.query)
			if len(response) > 0 {
				_, _ = conn.WriteTo(response, request.addr)
			}
			log.Printf("UDP query queue full; request rejected")
		}
	}
}

func (s *server) udpWorker(conn net.PacketConn, requests <-chan udpRequest) {
	for request := range requests {
		response, err := s.answer(request.query, false)
		if err != nil {
			log.Printf("UDP query: %v", err)
			response = serverFailure(request.query)
		}
		if len(response) > 0 {
			_, _ = conn.WriteTo(response, request.addr)
		}
	}
}

func (s *server) serveTCP(ln net.Listener) {
	defer ln.Close()
	for {
		conn, err := ln.Accept()
		if err != nil {
			log.Printf("TCP accept: %v", err)
			return
		}
		select {
		case s.tcpSlots <- struct{}{}:
			go func() {
				defer func() { <-s.tcpSlots }()
				s.handleTCP(conn)
			}()
		default:
			_ = conn.Close()
			log.Printf("TCP connection limit reached; connection rejected")
		}
	}
}

func (s *server) handleTCP(conn net.Conn) {
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(s.timeout))
	var length [2]byte
	if _, err := io.ReadFull(conn, length[:]); err != nil {
		return
	}
	n := int(binary.BigEndian.Uint16(length[:]))
	if n < dnsHeaderLen || n > 65535 {
		return
	}
	query := make([]byte, n)
	if _, err := io.ReadFull(conn, query); err != nil {
		return
	}
	response, err := s.answer(query, true)
	if err != nil {
		log.Printf("TCP query: %v", err)
		response = serverFailure(query)
	}
	if len(response) == 0 || len(response) > 65535 {
		return
	}
	binary.BigEndian.PutUint16(length[:], uint16(len(response)))
	_, _ = conn.Write(append(length[:], response...))
}

func (s *server) answer(query []byte, tcp bool) ([]byte, error) {
	name, qtype, questionEnd, err := parseQuestion(query)
	if err != nil {
		return nil, err
	}
	if qtype == typeAAAA && s.shouldFilterAAAA(name) {
		return noData(query, questionEnd), nil
	}
	if tcp {
		return s.forwardTCP(query)
	}
	return s.forwardUDP(query)
}

func (s *server) shouldFilterAAAA(name string) bool {
	return s.filterAllAAAA || s.filtered(name)
}

func (s *server) filtered(name string) bool {
	name = strings.TrimSuffix(strings.ToLower(name), ".")
	for _, suffix := range s.domains {
		if name == suffix || strings.HasSuffix(name, "."+suffix) {
			return true
		}
	}
	return false
}

func parseQuestion(msg []byte) (string, uint16, int, error) {
	if len(msg) < dnsHeaderLen || binary.BigEndian.Uint16(msg[4:6]) != 1 {
		return "", 0, 0, errors.New("unsupported DNS question count")
	}
	pos := dnsHeaderLen
	var labels []string
	for {
		if pos >= len(msg) {
			return "", 0, 0, io.ErrUnexpectedEOF
		}
		length := int(msg[pos])
		pos++
		if length == 0 {
			break
		}
		if length&0xc0 != 0 || length > 63 || pos+length > len(msg) {
			return "", 0, 0, errors.New("invalid question name")
		}
		labels = append(labels, string(msg[pos:pos+length]))
		pos += length
	}
	if pos+4 > len(msg) {
		return "", 0, 0, io.ErrUnexpectedEOF
	}
	qtype := binary.BigEndian.Uint16(msg[pos : pos+2])
	return strings.Join(labels, "."), qtype, pos + 4, nil
}

func noData(query []byte, questionEnd int) []byte {
	response := append([]byte(nil), query[:questionEnd]...)
	flags := binary.BigEndian.Uint16(response[2:4])
	flags = (flags | 0x8000 | 0x0080) &^ 0x0200
	binary.BigEndian.PutUint16(response[2:4], flags)
	binary.BigEndian.PutUint16(response[6:8], 0)
	binary.BigEndian.PutUint16(response[8:10], 0)
	binary.BigEndian.PutUint16(response[10:12], 0)
	return response
}

func serverFailure(query []byte) []byte {
	if len(query) < dnsHeaderLen {
		return nil
	}
	end := len(query)
	if _, _, qend, err := parseQuestion(query); err == nil {
		end = qend
	}
	response := append([]byte(nil), query[:end]...)
	flags := binary.BigEndian.Uint16(response[2:4])
	flags = (flags | 0x8000 | 0x0080 | 0x0002) &^ 0x000d
	binary.BigEndian.PutUint16(response[2:4], flags)
	binary.BigEndian.PutUint16(response[6:8], 0)
	binary.BigEndian.PutUint16(response[8:10], 0)
	binary.BigEndian.PutUint16(response[10:12], 0)
	return response
}

func (s *server) forwardUDP(query []byte) ([]byte, error) {
	deadline := time.Now().Add(s.timeout)
	var lastErr error
	for index, upstream := range s.upstreams {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			break
		}
		serversLeft := len(s.upstreams) - index
		attemptTimeout := remaining / time.Duration(serversLeft)
		if attemptTimeout < 250*time.Millisecond {
			attemptTimeout = remaining
		}

		conn, err := net.DialTimeout("udp4", upstream, attemptTimeout)
		if err != nil {
			lastErr = err
			continue
		}
		_ = conn.SetDeadline(time.Now().Add(attemptTimeout))
		if _, err = conn.Write(query); err == nil {
			buf := make([]byte, 65535)
			var n int
			n, err = conn.Read(buf)
			if err == nil {
				conn.Close()
				return append([]byte(nil), buf[:n]...), nil
			}
		}
		conn.Close()
		lastErr = err
	}
	if lastErr == nil {
		lastErr = errors.New("upstream timeout")
	}
	return nil, fmt.Errorf("all UDP upstreams failed: %w", lastErr)
}

func (s *server) forwardTCP(query []byte) ([]byte, error) {
	if len(query) > 65535 {
		return nil, fmt.Errorf("query too large: %d", len(query))
	}
	var lastErr error
	for _, upstream := range s.upstreams {
		response, err := s.forwardTCPTo(query, upstream)
		if err == nil {
			return response, nil
		}
		lastErr = err
	}
	return nil, fmt.Errorf("all TCP upstreams failed: %w", lastErr)
}

func (s *server) forwardTCPTo(query []byte, upstream string) ([]byte, error) {
	conn, err := net.DialTimeout("tcp4", upstream, s.timeout)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(s.timeout))
	var length [2]byte
	binary.BigEndian.PutUint16(length[:], uint16(len(query)))
	if _, err := conn.Write(append(length[:], query...)); err != nil {
		return nil, err
	}
	if _, err := io.ReadFull(conn, length[:]); err != nil {
		return nil, err
	}
	n := int(binary.BigEndian.Uint16(length[:]))
	if n < dnsHeaderLen {
		return nil, errors.New("short upstream response")
	}
	response := make([]byte, n)
	_, err = io.ReadFull(conn, response)
	return response, err
}
