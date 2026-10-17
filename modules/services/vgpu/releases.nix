# vGPU releases newer than vgpu4nixos packages, host and guests must run the same one.
# The host zip isn't public, its hash is that of the file NVIDIA hands out: `nix hash file --type sha256 <zip>`.
# Guest drivers come from Google: `nix store prefetch-file https://storage.googleapis.com/nvidia-drivers-us-public/GRID/vGPU<release>/NVIDIA-Linux-x86_64-<guest>-grid.run`
{
  "19.6" = {
    host = "580.178.05";
    guest = "580.178.04";
    windows = "582.78";
    zipSha256 = "sha256-m9tfnQ9bezBqCtj9YZfllTA8oshGwYslgBPYyaVC78o=";
    guestSha256 = "sha256-ZROyvWQxtQLOaGxvVGsZR7dXcQemEyzruA+wipVAJj8=";
  };
}
