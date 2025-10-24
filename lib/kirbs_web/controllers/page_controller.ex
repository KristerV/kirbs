defmodule KirbsWeb.PageController do
  use KirbsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end

  def serve_upload(conn, %{"filename" => filename}) do
    upload_dir = Application.get_env(:kirbs, :image_upload_dir)
    file_path = Path.join(upload_dir, filename)

    if File.exists?(file_path) do
      conn
      |> put_resp_content_type("image/jpeg")
      |> send_file(200, file_path)
    else
      conn
      |> put_status(404)
      |> text("Image not found")
    end
  end
end
