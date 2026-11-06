package storage

// Client talks to SeaweedFS (master / filer). TODO: implement upload, get, delete, collections.
type Client struct {
	FilerURL  string
	MasterURL string
}

func NewClient(filerURL, masterURL string) *Client {
	return &Client{FilerURL: filerURL, MasterURL: masterURL}
}
