This is a small utility that takes an S3 url and returns a presigned url to upload/download files.

This can be used to move files between servers that you don't want to make a IAM user for or put credentials on. It can also be used to reduce the amount of bandwidth you transfer around by passing around essentially pointers to s3 files rather than pushing the whole file around.

Example
```
» presigner us-east-1 /somerandomfile.tar random-s3-bucket -v put -d 21600 -c
curl -X PUT 'https://random-s3-bucket.s3.amazonaws.com/somerandomfile.tar?X-Amz-Signature=af0d709e00e7021c1e9f3391c45534d0e89a568faf3d6e292d486a8b719636c1&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIZ4AH2BM3FQU5KPQ/20190220/us-east-1/s3/aws4_request&X-Amz-Date=20190220T031839Z&X-Amz-Expires=21600&X-Amz-SignedHeaders=host' --upload-file
```
