package storage

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net/http"
	"time"

	"github.com/aws/aws-sdk-go-v2/aws"
	"github.com/aws/aws-sdk-go-v2/config"
	"github.com/aws/aws-sdk-go-v2/credentials"
	"github.com/aws/aws-sdk-go-v2/service/s3"
)

// R2 - Cloudflare R2 client (S3-compatible).
// Setup:
//   - Create bucket at dash.cloudflare.com/r2
//   - Create API token with R2:Edit
//   - Endpoint: https://<ACCOUNT_ID>.r2.cloudflarestorage.com
type R2 struct {
	client    *s3.Client
	bucket    string
	publicURL string // optional CDN front (e.g. https://cdn.tropia.vn)
}

type R2Config struct {
	AccountID       string
	AccessKeyID     string
	SecretAccessKey string
	Bucket          string
	PublicURL       string
}

func NewR2(ctx context.Context, cfg R2Config) (*R2, error) {
	if cfg.AccountID == "" || cfg.AccessKeyID == "" || cfg.SecretAccessKey == "" {
		return nil, fmt.Errorf("R2 credentials missing")
	}
	endpoint := fmt.Sprintf("https://%s.r2.cloudflarestorage.com", cfg.AccountID)
	awsCfg, err := config.LoadDefaultConfig(ctx,
		config.WithRegion("auto"),
		config.WithCredentialsProvider(credentials.NewStaticCredentialsProvider(cfg.AccessKeyID, cfg.SecretAccessKey, "")),
	)
	if err != nil {
		return nil, err
	}
	client := s3.NewFromConfig(awsCfg, func(o *s3.Options) {
		o.BaseEndpoint = aws.String(endpoint)
		o.UsePathStyle = true
	})
	return &R2{client: client, bucket: cfg.Bucket, publicURL: cfg.PublicURL}, nil
}

// Upload streams data to R2.
func (r *R2) Upload(ctx context.Context, key, contentType string, data []byte) (string, error) {
	_, err := r.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(r.bucket),
		Key:         aws.String(key),
		Body:        bytes.NewReader(data),
		ContentType: aws.String(contentType),
		ACL:         "public-read",
	})
	if err != nil {
		return "", err
	}
	return r.URLFor(key), nil
}

// UploadStream uploads from an io.Reader (for large files like VOD).
func (r *R2) UploadStream(ctx context.Context, key, contentType string, body io.Reader) (string, error) {
	_, err := r.client.PutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(r.bucket),
		Key:         aws.String(key),
		Body:        body,
		ContentType: aws.String(contentType),
		ACL:         "public-read",
	})
	if err != nil {
		return "", err
	}
	return r.URLFor(key), nil
}

func (r *R2) Delete(ctx context.Context, key string) error {
	_, err := r.client.DeleteObject(ctx, &s3.DeleteObjectInput{
		Bucket: aws.String(r.bucket),
		Key:    aws.String(key),
	})
	return err
}

// URLFor returns the public URL.
func (r *R2) URLFor(key string) string {
	return r.PublicBaseURL() + "/" + key
}

// PublicBaseURL returns the origin/prefix every object URL is built on (no
// trailing slash). Used to verify a client-supplied URL actually points at our
// bucket before we persist it (prevents arbitrary-URL injection on create).
func (r *R2) PublicBaseURL() string {
	if r.publicURL != "" {
		return r.publicURL
	}
	return fmt.Sprintf("https://pub-%s.r2.dev", r.bucket)
}

// PresignPut creates a presigned URL clients can PUT to directly (avoiding backend bandwidth).
func (r *R2) PresignPut(ctx context.Context, key, contentType string, ttl time.Duration) (string, error) {
	presigner := s3.NewPresignClient(r.client)
	out, err := presigner.PresignPutObject(ctx, &s3.PutObjectInput{
		Bucket:      aws.String(r.bucket),
		Key:         aws.String(key),
		ContentType: aws.String(contentType),
	}, s3.WithPresignExpires(ttl))
	if err != nil {
		return "", err
	}
	return out.URL, nil
}

// HealthCheck - simple GET on bucket
func (r *R2) HealthCheck(ctx context.Context) error {
	ctx, cancel := context.WithTimeout(ctx, 5*time.Second)
	defer cancel()
	_, err := r.client.HeadBucket(ctx, &s3.HeadBucketInput{Bucket: aws.String(r.bucket)})
	if err != nil {
		var httpErr interface{ HTTPStatusCode() int }
		if as, ok := err.(httpFamilyError); ok {
			httpErr = as
		}
		if httpErr != nil && httpErr.HTTPStatusCode() == http.StatusNotFound {
			return fmt.Errorf("bucket %s not found", r.bucket)
		}
		return err
	}
	return nil
}

type httpFamilyError interface {
	HTTPStatusCode() int
}
