load("//appengine:go_appengine.bzl", _go_appengine ="go_appengine")
load("//appengine:go_appengine.bzl", _go_appengine_project = "appengine_project")
load("//appengine:sdk.bzl", _go_appengine_repository = "appengine_repositories")

go_appengine = _go_appengine
go_appengine_project = _go_appengine_project
go_appengine_repositories = _go_appengine_repository
