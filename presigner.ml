open Aws_s3

exception Incorrect_Time_Format of string

exception Incorrect_Bucket_Name of string

exception Incorrect_AWS_Error of string

let empty_hash = Authorization.hash_sha256 "" |> Authorization.to_hex

let sprintf = Printf.sprintf

let verb_to_string = function `Get -> "GET" | `Put -> "PUT"

let get_bucket url =
  match Uri.host url with
  | Some b ->
      b
  | None ->
      raise (Incorrect_Bucket_Name "Need a bucket in the url.")

let parse_uri url =
  let bucket = get_bucket url in
  let path = Uri.path url in
  (bucket, path)

let process_body b default =
  let region_regex = Str.regexp "\\<Region\\>\\([a-z0-9-]*\\)\\</Region\\>" in
  let error_regex = Str.regexp "Error" in
  match Str.search_forward error_regex b 0 with
  | exception Not_found ->
      default
  | _ -> (
    match Str.search_forward region_regex b 0 with
    | exception Not_found ->
        raise
          (Incorrect_AWS_Error
             (sprintf "AWS is missing a region field, it returned:\n %s" b))
    | _ ->
        Str.matched_group 1 b )

(*A bunch of the formatting/structure for this code was borrowed from https://github.com/andersfugmann/aws-s3 *)
let get_region ~(credentials : Credentials.t) ~bucket () =
  let service = "s3" in
  let now = Ptime_clock.now () in
  let (y, m, d), ((h, mi, s), _) = Ptime.to_date_time now in
  let verb = "GET" in
  let scheme = "https" in
  let date = sprintf "%02d%02d%02d" y m d in
  let time = sprintf "%02d%02d%02d" h mi s in
  let formatted_date =
    sprintf "%02.0f%02.0f%02.0fT%02.0f%02.0f%02.0fZ" (float_of_int y)
      (float_of_int m) (float_of_int d) (float_of_int h) (float_of_int mi)
      (float_of_int s)
  in
  let host = "s3.amazonaws.com" in
  let path = sprintf "/%s" bucket in
  let region = "us-east-1" in
  let headers = Headers.empty in
  let headers =
    List.fold_left
      (fun acc x -> Headers.add ~key:(fst x) ~value:(snd x) acc)
      headers
      [("Host", host); ("Date", formatted_date)]
  in
  let headers = match credentials.token with
  | Some t -> Headers.add ~key:"X-Amz-Security-Token" ~value:t headers
  | None -> headers
  in
  let scope = Authorization.make_scope ~date ~region ~service in
  let signing_key =
    Authorization.make_signing_key ~date ~region ~service ~credentials ()
  in
  let signature, signed_headers =
    Authorization.make_signature ~date ~time ~verb ~path ~headers ~query:[]
      ~signing_key ~scope ~payload_sha:empty_hash
  in
  let algo = "AWS4-HMAC-SHA256" in
  let creds =
    sprintf "%s/%s/%s/s3/aws4_request" credentials.Credentials.access_key date
      region
  in
  let auth_header =
    sprintf " %s Credential=%s, SignedHeaders=%s, Signature=%s" algo creds
      signed_headers signature
  in
  let cohttp_headers = Cohttp.Header.init_with "Host" host in
  let headers = Cohttp.Header.add cohttp_headers "Authorization" auth_header in
  let headers = Cohttp.Header.add headers "Date" formatted_date in
  let headers = Cohttp.Header.add headers "x-amz-content-sha256" empty_hash in
  let headers = match credentials.token with
  | Some t -> Cohttp.Header.add headers "X-Amz-Security-Token" t
  | None -> headers
  in
  let%lwt _resp, body =
    Cohttp_lwt_unix.Client.get (Uri.make ~scheme ~host ~path ()) ~headers
  in
  let%lwt body_string = Cohttp_lwt.Body.to_string body in
  Lwt.return (Region.of_string (process_body body_string region))

let main url (verb : [`Get | `Put]) duration gen_command region =
  let%lwt credentials =
    match%lwt Aws_s3_lwt.Credentials.Helper.get_credentials () with
    | Ok x ->
        Lwt.return x
    | Error e ->
        raise e
  in
  let date =
    match Ptime.of_float_s (Unix.gettimeofday ()) with
    | Some x ->
        x
    | None ->
        raise
          (Incorrect_Time_Format
             "Current time isn't formatted correctly!? (this generally \
              shouldn't happen unless something is very wrong.)")
  in
  let bucket, path = parse_uri url in
  let%lwt region =
    match region with
    | Some r ->
        Lwt.return (Region.of_string r)
    | None ->
        get_region ~credentials ~bucket ()
  in
  let presigned =
    Authorization.make_presigned_url ~credentials ~date ~region ~path ~bucket
      ~verb ~duration ()
    |> Uri.to_string
  in
  match gen_command with
  | false ->
      Lwt_io.printl presigned
  | true -> (
    match verb with
    | `Put ->
        Lwt_io.printl
          (Printf.sprintf "curl -X PUT \'%s\' --upload-file" presigned)
    | `Get ->
        Lwt_io.printl
          (Printf.sprintf "curl -X %s \'%s\'" (verb_to_string verb) presigned)
    )

open Cmdliner

let uri =
  let parse s = Ok (Uri.of_string s) in
  Arg.conv (parse, Uri.pp_hum)

let url =
  let doc = "The S3 url to generate the presigned url from." in
  Arg.(required & pos 0 (some uri) None & info [] ~docv:"URL" ~doc)

let verb =
  let doc = "If it should be a GET or a PUT." in
  let verb = Arg.enum [("get", `Get); ("put", `Put)] in
  Arg.(value & opt verb `Get & info ["v"; "verb"] ~docv:"VERB" ~doc)

let duration =
  let doc = "For how many seconds the link should stay active." in
  Arg.(value & opt int 21600 & info ["d"; "duration"] ~docv:"duration" ~doc)

let region =
  let doc =
    "Tell the region in advance, this is mostly useful for bulk operations or \
     speeding up operations."
  in
  Arg.(
    value & opt (some string) None & info ["r"; "region"] ~docv:"region" ~doc)

let gen_command =
  let doc = "Generates a mostly complete curl command for usage." in
  Arg.(value & flag & info ["c"; "command"] ~doc)

let main_t =
  Term.(
    const Lwt_main.run
    $ (const main $ url $ verb $ duration $ gen_command $ region))

let info =
  let doc =
    "Creates a simple link to a file for either uploading or downloading from \
     S3 that is preauthenticated."
  in
  let man =
    [`S Manpage.s_bugs; `P "File an issue on the project issue tracker."]
  in
  Term.info "presigner" ~version:"%%VERSION%%" ~doc ~exits:Term.default_exits
    ~man

let () = Term.exit @@ Term.eval (main_t, info)
