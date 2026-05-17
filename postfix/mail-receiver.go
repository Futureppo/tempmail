package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"mime"
	"mime/multipart"
	"net/http"
	"net/mail"
	"os"
	"strings"
	"time"
)

type deliverPayload struct {
	Recipient string `json:"recipient"`
	Sender    string `json:"sender"`
	Subject   string `json:"subject"`
	BodyText  string `json:"body_text"`
	BodyHTML  string `json:"body_html"`
	Raw       string `json:"raw"`
}

func main() {
	log.SetOutput(os.Stderr)
	if len(os.Args) < 2 {
		log.Print("usage: mail-receiver <recipient>")
		os.Exit(1)
	}

	rawBytes, err := io.ReadAll(os.Stdin)
	if err != nil {
		log.Printf("read stdin: %v", err)
		os.Exit(75)
	}
	if len(rawBytes) == 0 {
		return
	}

	raw := string(rawBytes)
	msg, err := mail.ReadMessage(bytes.NewReader(rawBytes))
	if err != nil {
		log.Printf("parse mail: %v", err)
		os.Exit(75)
	}

	bodyText, bodyHTML := extractBodies(msg)
	payload := deliverPayload{
		Recipient: strings.ToLower(strings.TrimSpace(os.Args[1])),
		Sender:    msg.Header.Get("From"),
		Subject:   msg.Header.Get("Subject"),
		BodyText:  bodyText,
		BodyHTML:  bodyHTML,
		Raw:       raw,
	}
	if err := deliver(payload); err != nil {
		log.Printf("deliver: %v", err)
		os.Exit(75)
	}
}

func extractBodies(msg *mail.Message) (string, string) {
	mediaType, params, err := mime.ParseMediaType(msg.Header.Get("Content-Type"))
	if err == nil && strings.HasPrefix(strings.ToLower(mediaType), "multipart/") {
		return extractMultipart(msg.Body, params["boundary"])
	}

	body, _ := io.ReadAll(io.LimitReader(msg.Body, 20<<20))
	if strings.EqualFold(mediaType, "text/html") {
		return "", string(body)
	}
	return string(body), ""
}

func extractMultipart(r io.Reader, boundary string) (string, string) {
	if boundary == "" {
		body, _ := io.ReadAll(io.LimitReader(r, 20<<20))
		return string(body), ""
	}

	var textBody, htmlBody string
	mr := multipart.NewReader(r, boundary)
	for {
		part, err := mr.NextPart()
		if err == io.EOF {
			break
		}
		if err != nil {
			break
		}
		mediaType, params, _ := mime.ParseMediaType(part.Header.Get("Content-Type"))
		mediaType = strings.ToLower(mediaType)
		if strings.HasPrefix(mediaType, "multipart/") {
			nestedText, nestedHTML := extractMultipart(part, params["boundary"])
			if textBody == "" {
				textBody = nestedText
			}
			if htmlBody == "" {
				htmlBody = nestedHTML
			}
			continue
		}
		body, _ := io.ReadAll(io.LimitReader(part, 20<<20))
		switch mediaType {
		case "text/plain":
			if textBody == "" {
				textBody = string(body)
			}
		case "text/html":
			if htmlBody == "" {
				htmlBody = string(body)
			}
		}
	}
	return textBody, htmlBody
}

func deliver(payload deliverPayload) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	apiURL := strings.TrimRight(os.Getenv("API_URL"), "/")
	if apiURL == "" {
		apiURL = "http://api:8080"
	}

	req, err := http.NewRequest(http.MethodPost, apiURL+"/internal/deliver", bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	client := &http.Client{Timeout: 10 * time.Second}
	res, err := client.Do(req)
	if err != nil {
		return err
	}
	defer res.Body.Close()
	if res.StatusCode < 200 || res.StatusCode >= 300 {
		return fmt.Errorf("api returned HTTP %d", res.StatusCode)
	}
	return nil
}
