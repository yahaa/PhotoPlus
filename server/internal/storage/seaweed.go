// Package storage reads and writes photo objects through the SeaweedFS filer.
package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strings"
)

// ErrNotFound means the object does not exist.
var ErrNotFound = errors.New("object not found")

// Object is an open object body plus the HTTP metadata worth forwarding.
type Object struct {
	Body         io.ReadCloser
	Status       int
	ContentType  string
	Length       string
	ContentRange string
}

// Client talks to the SeaweedFS filer. The collection separates safety tiers.
type Client struct {
	FilerURL string
	HTTP     *http.Client
}

// NewClient returns a filer client. It sets no overall timeout: originals can be large.
func NewClient(filerURL string) *Client {
	return &Client{FilerURL: strings.TrimRight(filerURL, "/"), HTTP: &http.Client{}}
}

func (c *Client) objectURL(tier, id, kind string) string {
	path := fmt.Sprintf("/photoplus/%s/%s/%s/%s", tier, id[:2], id, kind)
	return c.FilerURL + path + "?collection=" + url.QueryEscape(tier)
}

// Put streams one object to the filer. size < 0 sends it chunked.
func (c *Client) Put(ctx context.Context, tier, id, kind, contentType string, body io.Reader, size int64) error {
	req, err := http.NewRequestWithContext(ctx, http.MethodPut, c.objectURL(tier, id, kind), body)
	if err != nil {
		return err
	}
	req.ContentLength = size
	req.Header.Set("Content-Type", contentType)
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer drain(resp)
	if resp.StatusCode >= http.StatusMultipleChoices {
		return fmt.Errorf("filer put %s: %s", kind, resp.Status)
	}
	return nil
}

// Size returns the stored size of an object, or ErrNotFound.
func (c *Client) Size(ctx context.Context, tier, id, kind string) (int64, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, c.objectURL(tier, id, kind), nil)
	if err != nil {
		return 0, err
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return 0, err
	}
	defer drain(resp)
	if resp.StatusCode == http.StatusNotFound {
		return 0, ErrNotFound
	}
	if resp.StatusCode != http.StatusOK {
		return 0, fmt.Errorf("filer head %s: %s", kind, resp.Status)
	}
	return resp.ContentLength, nil
}

// Get opens an object, forwarding rangeHeader when set. The caller closes Body.
func (c *Client) Get(ctx context.Context, tier, id, kind, rangeHeader string) (*Object, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, c.objectURL(tier, id, kind), nil)
	if err != nil {
		return nil, err
	}
	if rangeHeader != "" {
		req.Header.Set("Range", rangeHeader)
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return nil, err
	}
	switch resp.StatusCode {
	case http.StatusOK, http.StatusPartialContent:
		return &Object{
			Body:         resp.Body,
			Status:       resp.StatusCode,
			ContentType:  resp.Header.Get("Content-Type"),
			Length:       resp.Header.Get("Content-Length"),
			ContentRange: resp.Header.Get("Content-Range"),
		}, nil
	case http.StatusNotFound:
		drain(resp)
		return nil, ErrNotFound
	default:
		drain(resp)
		return nil, fmt.Errorf("filer get %s: %s", kind, resp.Status)
	}
}

// Delete removes every object stored for a photo. A missing photo is not an error.
func (c *Client) Delete(ctx context.Context, tier, id string) error {
	target := fmt.Sprintf("%s/photoplus/%s/%s/%s?recursive=true", c.FilerURL, tier, id[:2], id)
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, target, nil)
	if err != nil {
		return err
	}
	resp, err := c.HTTP.Do(req)
	if err != nil {
		return err
	}
	defer drain(resp)
	if resp.StatusCode >= http.StatusMultipleChoices && resp.StatusCode != http.StatusNotFound {
		return fmt.Errorf("filer delete: %s", resp.Status)
	}
	return nil
}

func drain(resp *http.Response) {
	_, _ = io.Copy(io.Discard, resp.Body)
	_ = resp.Body.Close()
}
