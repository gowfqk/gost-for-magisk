package main

import (
	"encoding/binary"
	"net"
	"os"
	"testing"
	"time"
)

func TestValidateModuleConfig(t *testing.T) {
	path := t.TempDir() + "/config.json"
	valid := []byte(`{"proxy_type":"redirect","listen_port":1080,"webui_port":8080,"upstream":{"enabled":false},"routing":{"direct_uids":[0,1000]}}`)
	if err := os.WriteFile(path, valid, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := validateModuleConfig(path); err != nil {
		t.Fatalf("valid config rejected: %v", err)
	}
	malformed := []byte(`{"proxy_type":"redirect","listen_port":1080,,"webui_port":8080}`)
	if err := os.WriteFile(path, malformed, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := validateModuleConfig(path); err == nil {
		t.Fatal("malformed JSON was accepted")
	}
}

func makeQuery(name string, qtype uint16) []byte {
	msg := make([]byte, 12)
	binary.BigEndian.PutUint16(msg[0:2], 0x1234)
	binary.BigEndian.PutUint16(msg[2:4], 0x0100)
	binary.BigEndian.PutUint16(msg[4:6], 1)
	for _, label := range splitName(name) {
		msg = append(msg, byte(len(label)))
		msg = append(msg, label...)
	}
	msg = append(msg, 0, byte(qtype>>8), byte(qtype), 0, 1)
	return msg
}

func splitName(name string) []string {
	var labels []string
	start := 0
	for i := 0; i <= len(name); i++ {
		if i == len(name) || name[i] == '.' {
			labels = append(labels, name[start:i])
			start = i + 1
		}
	}
	return labels
}

func TestParseUpstreams(t *testing.T) {
	got := parseUpstreams("223.5.5.5, 119.29.29.29:53,223.5.5.5")
	want := []string{"223.5.5.5:53", "119.29.29.29:53"}
	if len(got) != len(want) {
		t.Fatalf("parseUpstreams() = %#v, want %#v", got, want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("parseUpstreams()[%d] = %q, want %q", i, got[i], want[i])
		}
	}
}

func TestParseQuestion(t *testing.T) {
	query := makeQuery("www.google.com", typeAAAA)
	name, qtype, end, err := parseQuestion(query)
	if err != nil || name != "www.google.com" || qtype != typeAAAA || end != len(query) {
		t.Fatalf("parseQuestion() = %q, %d, %d, %v", name, qtype, end, err)
	}
}

func TestFilteredSuffixBoundary(t *testing.T) {
	s := server{domains: []string{"google.com"}}
	for _, name := range []string{"google.com", "www.google.com", "WWW.GOOGLE.COM."} {
		if !s.filtered(name) {
			t.Errorf("expected %q to be filtered", name)
		}
	}
	for _, name := range []string{"notgoogle.com", "google.com.example.org"} {
		if s.filtered(name) {
			t.Errorf("did not expect %q to be filtered", name)
		}
	}
}

func TestFilterAllAAAA(t *testing.T) {
	s := server{domains: []string{"google.com"}, filterAllAAAA: true}
	if !s.shouldFilterAAAA("unrelated.example") {
		t.Fatal("global IPv4-only mode did not filter unrelated AAAA query")
	}
	s.filterAllAAAA = false
	if s.shouldFilterAAAA("unrelated.example") {
		t.Fatal("domain-only mode filtered unrelated AAAA query")
	}
	if !s.shouldFilterAAAA("www.google.com") {
		t.Fatal("domain-only mode did not filter configured suffix")
	}
}

func TestNoDataPreservesQuestion(t *testing.T) {
	query := makeQuery("google.com", typeAAAA)
	response := noData(query, len(query))
	if binary.BigEndian.Uint16(response[0:2]) != 0x1234 {
		t.Fatal("transaction ID changed")
	}
	if binary.BigEndian.Uint16(response[2:4])&0x8000 == 0 {
		t.Fatal("response bit is not set")
	}
	if got := binary.BigEndian.Uint16(response[6:8]); got != 0 {
		t.Fatalf("answer count = %d, want 0", got)
	}
	if string(response[12:]) != string(query[12:]) {
		t.Fatal("question section changed")
	}
}

func TestForwardUDPUsesTotalTimeout(t *testing.T) {
	silent, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer silent.Close()

	listener, err := net.ListenPacket("udp4", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer listener.Close()

	go func() {
		buf := make([]byte, 65535)
		n, addr, readErr := listener.ReadFrom(buf)
		if readErr == nil {
			_, _ = listener.WriteTo(buf[:n], addr)
		}
	}()

	s := server{
		upstreams: []string{silent.LocalAddr().String(), listener.LocalAddr().String()},
		timeout:   2 * time.Second,
	}
	query := makeQuery("example.com", 1)
	started := time.Now()
	response, err := s.forwardUDP(query)
	if err != nil {
		t.Fatalf("forwardUDP() error = %v", err)
	}
	if string(response) != string(query) {
		t.Fatal("unexpected upstream response")
	}
	if elapsed := time.Since(started); elapsed >= 2*time.Second {
		t.Fatalf("forwardUDP() took %v, want less than total timeout", elapsed)
	}
}
