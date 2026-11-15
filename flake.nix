{
  description = "Helpers for the shared Renovate preset";

  outputs =
    { self }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      app = {
        type = "app";
        program = "${self}/go-vendor-hash.sh";
        meta.description = "Rewrite the buildGoModule vendorHash after a Go dependency update";
      };
    in
    {
      apps = builtins.listToAttrs (
        map (system: {
          name = system;
          value.go-vendor-hash = app;
        }) systems
      );
    };
}
