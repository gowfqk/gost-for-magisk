package main

import (
	"encoding/binary"
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
	dnsHeaderLen = 12
	typeAAAA     = 28
)

type server struct {
	listen   string
	upstream string
	timeout  time.Duration
	domains  []string
}

func main() {
	listen := flag.String("listen", "127.0.0.1:1053", "UDP/TCP listen address")
	upstream := flag.String("upstream", "223.5.5.5:53", "upstream DNS server")
	domainFile := flag.String("domains", "", "domain suffix file")
	timeout := flag.Duration("timeout", 5*time.Second, "upstream timeout")
	flag.Parse()

	domains, err := loadDomains(*domainFile)
	if err != nil {
		log.Fatalf("load domains: %v", err)
	}
	if len(domains) == 0 {
		log.Fatal("no IPv4-only domains configured")
	}

	s := &server{listen: *listen, upstream: *upstream, timeout: *timeout, domains: domains}
	udpConn, err := net.ListenPacket("udp4", s.listen)
	if err != nil {
		log.Fatalf("listen UDP %s: %v", s.listen, err)
	}
	tcpLn, err := net.Listen("tcp4", s.listen)
	if err != nil {
		udpConn.Close()
		log.Fatalf("listen TCP %s: %v", s.listen, err)
	}
	log.Printf("IPv4-only DNS filter listening on %s, upstream %s, domains %d", s.listen, s.upstream, len(s.domains))

	var wg sync.WaitGroup
	wg.Add(2)
	go func() { defer wg.Done(); s.serveUDP(udpConn) }()
	go func() { defer wg.Done(); s.serveTCP(tcpLn) }()
	wg.Wait()
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
	buf := make([]byte, 65535)
	for {
		n, addr, err := conn.ReadFrom(buf)
		if err != nil {
			log.Printf("UDP read: %v", err)
			return
		}
		query := append([]byte(nil), buf[:n]...)
		go func() {
			response, err := s.answer(query, false)
			if err != nil {
				log.Printf("UDP query: %v", err)
				response = serverFailure(query)
			}
			if len(response) > 0 {
				_, _ = conn.WriteTo(response, addr)
			}
		}()
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
		go s.handleTCP(conn)
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
	if qtype == typeAAAA && s.filtered(name) {
		return noData(query, questionEnd), nil
	}
	if tcp {
		return s.forwardTCP(query)
	}
	return s.forwardUDP(query)
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
	conn, err := net.DialTimeout("udp4", s.upstream, s.timeout)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(s.timeout))
	if _, err := conn.Write(query); err != nil {
		return nil, err
	}
	buf := make([]byte, 65535)
	n, err := conn.Read(buf)
	if err != nil {
		return nil, err
	}
	return append([]byte(nil), buf[:n]...), nil
}

func (s *server) forwardTCP(query []byte) ([]byte, error) {
	conn, err := net.DialTimeout("tcp4", s.upstream, s.timeout)
	if err != nil {
		return nil, err
	}
	defer conn.Close()
	_ = conn.SetDeadline(time.Now().Add(s.timeout))
	if len(query) > 65535 {
		return nil, fmt.Errorf("query too large: %d", len(query))
	}
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
