package main

import (
	"encoding/binary"
	"testing"
)

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
