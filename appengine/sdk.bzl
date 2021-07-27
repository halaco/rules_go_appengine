
_CLOUD_SDK_BASE_URL = "https://dl.google.com/dl/cloudsdk/channels/rapid/downloads"
CLOUD_SDK_PLATFORM_ARCHIVE = "{}/google-cloud-sdk-322.0.0-linux-x86_64.tar.gz".format(
    _CLOUD_SDK_BASE_URL,
)
CLOUD_SDK_PLATFORM_SHA256 = "cac741b00578e56ebdc13e1b30a288efe41d1d306b249dbd35a99ebdd7a13f96"

def _appengine_download_cloud_sdk(repository_ctx):
    repository_ctx.download_and_extract(
        url = CLOUD_SDK_PLATFORM_ARCHIVE,
        output = ".",
        sha256 = CLOUD_SDK_PLATFORM_SHA256,
        stripPrefix = "google-cloud-sdk",
    )
    repository_ctx.template("BUILD", Label("//appengine:cloud_sdk.BUILD"))

appengine_download_cloud_sdk = repository_rule(
    local = False,
    implementation = _appengine_download_cloud_sdk,
)

def appengine_repositories():
    appengine_download_cloud_sdk(name = "io_halaco_google_cloud_sdk")
