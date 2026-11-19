defmodule MelodyStudioWeb.PageControllerTest do
  use MelodyStudioWeb.ConnCase

  import MelodyStudio.AccountsFixtures

  test "GET / shows the home page to visitors", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)
    assert html =~ "whole song"
    assert html =~ "Make my first song"
  end

  test "GET / links signed-in users to their songs", %{conn: conn} do
    html = conn |> log_in_user(user_fixture()) |> get(~p"/") |> html_response(200)
    assert html =~ "Go to my songs"
  end
end
