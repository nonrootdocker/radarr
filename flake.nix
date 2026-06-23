{
  description = "minimalbase + radarr service";
  inputs = {
    nixpkgs.follows = "minimalbase/nixpkgs";
    minimalbase.url = "github:nonrootdocker/minimalbase";
    radarr-src = {
      type = "tarball";
      url = "https://radarr.servarr.com/v1/update/master/updatefile?os=linux&runtime=netcore&arch=x64";
      flake = false;
    };
  };
  outputs = { self, nixpkgs, minimalbase, radarr-src }:
  let
    system = "x86_64-linux";
    pkgs = import nixpkgs {
      inherit system;
      config = {
        allowUnfree = true;
      };
    };
    opensslLib = pkgs.openssl.out;
    # ----------------------------
    # Radarr package
    # ----------------------------
    radarr = pkgs.stdenv.mkDerivation {
      pname = "radarr";
      version = "release";
      src = radarr-src;
      nativeBuildInputs = [
        pkgs.autoPatchelfHook
      ];
      buildInputs = [
        pkgs.icu
        pkgs.curl
        pkgs.sqlite
        opensslLib
        pkgs.zlib
        pkgs.lttng-ust_2_12
        pkgs.stdenv.cc.cc.lib
      ];
      installPhase = ''
        mkdir -p $out/app/Radarr
        cp -r . $out/app/Radarr/
      '';
    };
    # ----------------------------
    # Radarr version: the real product version is embedded in Core.dll as
    # the assembly reference "Radarr.Common, Version=N.N.N.N" (consistent
    # across Servarr apps). Exposed as the `version` output for CI tagging.
    # ----------------------------
    radarrVersion = pkgs.runCommand "radarr-version" {
      nativeBuildInputs = [ pkgs.binutils ];
    } ''
      strings ${radarr}/app/Radarr/Radarr.Core.dll \
        | grep -oE 'Radarr\.Common, Version=[0-9.]+' \
        | head -n1 | sed 's/.*Version=//' | tr -d '\n' > $out
    '';
    # ----------------------------
    # User database configuration (/etc/passwd)
    # ----------------------------
    passwdFile = pkgs.writeTextDir "etc/passwd" ''
      root:x:0:0:root:/root:/bin/sh
      radarr:x:1000:1000:radarr:/data:/bin/sh
    '';
    # ----------------------------
    # ABI generator (Points directly to Nix Store)
    # ----------------------------
    radarrAbi = pkgs.writeTextFile {
      name = "radarr-abi.json";
      text = builtins.toJSON {
        version = 2;
        process = {
          exec = "${radarr}/app/Radarr/Radarr";
          args = [
            "-nobrowser"
            "-data=/data"
          ];
        };
      };
      destination = "/app/main";
    };
  in {
    packages.${system} = {
      default = self.packages.${system}.radarr-image;
      version = radarrVersion;
      radarr-image = pkgs.dockerTools.buildImage {
        name = "radarr";
        tag = "latest";
        fromImage = minimalbase.packages.${system}.base-image;
        copyToRoot = pkgs.buildEnv {
          name = "root";
          paths = [
            pkgs.coreutils
            pkgs.tzdata
            pkgs.cacert
            radarr
            radarrAbi
            passwdFile
          ];
        };
        config = {
          Entrypoint = [ "${minimalbase.packages.${system}.container-init}/bin/container-init" ];
          User = "1000:1000";
          Env = [
            "PATH=/bin"
            "TZ=UTC"
            "LANG=en_US.UTF-8"
            "LD_LIBRARY_PATH=${pkgs.icu}/lib:${opensslLib}/lib:${pkgs.zlib}/lib:${pkgs.lttng-ust_2_12}/lib"
          ];
        };
      };
    };
  };
}
