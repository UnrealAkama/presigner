This is a small utility that takes an S3 url and returns a presigned url to upload/download files.

This can be used to move files between servers that you don't want to make a IAM user for or put credentials on. It can also be used to reduce the amount of bandwidth you transfer around by passing around essentially pointers to s3 files rather than pushing the whole file around.

Example
```
» presigner s3://dropbox/test 
https://eg-dropbox.s3.amazonaws.com/test?X-Amz-Signature=0583da96bb41e1cb42b5f6462bb6cb3613b5a9e594bb5e40e78a567a0cbe66a4&X-Amz-Algorithm=AWS4-HMAC-SHA256&X-Amz-Credential=AKIAIRPW5JGRSXEQSOQQ/20190904/us-east-1/s3/aws4_request&X-Amz-Date=20190904T121651Z&X-Amz-Expires=21600&X-Amz-SignedHeaders=host
```
