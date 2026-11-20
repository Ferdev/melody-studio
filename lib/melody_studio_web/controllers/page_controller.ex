defmodule MelodyStudioWeb.PageController do
  use MelodyStudioWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
