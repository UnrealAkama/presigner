open Aws_s3

exception Incorrect_Time_Format of string

let verb_to_string = function
  | `Get -> "GET"
  | `Put -> "PUT"

let main region path bucket (verb : [`Get | `Put]) duration gen_command =
  let%lwt _credentials = match%lwt Aws_s3_lwt.Credentials.Helper.get_credentials () with
  | Ok x -> Lwt.return x
  | Error e -> raise e
  in
  let credentials =
    Credentials.make ~access_key:_credentials.Credentials.access_key
      ~secret_key:(String.trim _credentials.Credentials.secret_key) ()
  in
  let date =
    match Ptime.of_float_s (Unix.gettimeofday ()) with
    | Some x -> x
    | None ->
        raise
          (Incorrect_Time_Format "Current time isn't formatted correctly!? (this generally shouldn't happen unless something is very wrong.)")
  in
  let region = Region.of_string region in
  let presigned = ( Authorization.make_presigned_url ~credentials ~date ~region ~path ~bucket ~verb
        ~duration ()
    |> Uri.to_string ) in
  match gen_command with
  | false -> Lwt_io.printl presigned
  | true ->
    match verb with
    | `Put -> Lwt_io.printl (Printf.sprintf "curl -X PUT \'%s\' --upload-file" presigned)
    | `Get -> Lwt_io.printl (Printf.sprintf "curl -X %s \'%s\'" (verb_to_string verb) presigned)

open Cmdliner

let region =
  let doc = "What region the upload/download objects are from." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"REGION" ~doc)

let path =
  let doc = "What path to upload/download objects from." in
  Arg.(required & pos 1 (some string) None & info [] ~docv:"PATH" ~doc)

let bucket =
  let doc = "Bucket that the path is located in." in
  Arg.(required & pos 2 (some string) None & info [] ~docv:"BUCKET" ~doc)

let verb =
  let doc = "If it should be a GET or a PUT." in
  let verb =  Arg.enum ["get", `Get; "put", `Put] in
  Arg.(value & opt verb `Get & info ["v"; "verb"] ~docv:"VERB" ~doc)

let duration  =
  let doc = "For how many seconds the link should stay active." in
  Arg.(value & opt int 1800 & info ["d"; "duration"] ~docv:"duration" ~doc)

let gen_command =
  let doc = "Generates a complete curl command for usage." in
  Arg.(value & flag & info ["c"; "command"] ~doc)

let main_t = Term.(const Lwt_main.run $ (const main $ region $ path $ bucket $ verb $ duration $ gen_command))

let info =
  let doc = "Creates a simple link to a file for either uploading or downloading from curl." in
  let man = [
    `S Manpage.s_bugs;
    `P "Sends a slack message to Adam." ]
  in
  Term.info "charon" ~version:"%%VERSION%%" ~doc ~exits:Term.default_exits ~man

let () = Term.exit @@ Term.eval (main_t, info)
