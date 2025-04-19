{
  description = "Unified dev environment for the Dogebox";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-24.11";
    flake-utils.url = "github:numtide/flake-utils";

    dogeboxd = {
      url = "github:dogebox-wg/dogeboxd/dev-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    dkm = {
      url = "github:dogebox-wg/dkm/dev-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    dpanel = {
      url = "github:dogebox-wg/dpanel/dev-flake";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, dogeboxd, dkm, dpanel, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        upScript = pkgs.writeShellScriptBin "dbx-up" (builtins.readFile ./scripts/up.sh);
        setupScript = pkgs.writeShellScriptBin "dbx-setup" (builtins.readFile ./scripts/setup.sh);

        mkServiceUpScript = dbxSessionName: dbxStartCommand: dbxCWD: let
          pushd = "pushd ../${dbxSessionName}/" + (if dbxCWD == null then "" else dbxCWD);
        in pkgs.writeShellScriptBin "${dbxSessionName}-up" ''
          ${pushd}
            screen -dmS ${dbxSessionName} ${dbxStartCommand}
            echo "Started ${dbxSessionName} in screen session '${dbxSessionName}'"
            echo "Run 'screen -r ${dbxSessionName}' to attach to the session"
          popd
        '';

        mkTerminateSessionScript = sessionName:
          pkgs.writeShellScriptBin "${sessionName}-down" ''
          if screen -S ${sessionName} -Q select .; then
            screen -S ${sessionName} -X quit
            echo "Terminated screen session '${sessionName}'"
            exit 0
          else
            echo "No screen session '${sessionName}' found"
            exit 1
          fi
        '';

        mkAttachSessionScript = sessionName:
          pkgs.writeShellScriptBin "${sessionName}-attach" ''
          if screen -ls | grep -q "\.${sessionName}"; then
            exec screen -r ${sessionName}
          else
            echo "No screen session '${sessionName}' available to attach"
            exit 1
          fi
        '';

        mkServiceScripts = input:
          let
            sessionName = input.dbxSessionName.${system};
            startCommand = input.dbxStartCommand.${system};
            cwd = if builtins.hasAttr "dbxCWD" input && input.dbxCWD.${system} != null then input.dbxCWD.${system} else null;
          in {
            upScript = mkServiceUpScript sessionName startCommand cwd;
            downScript = mkTerminateSessionScript sessionName;
            attachScript = mkAttachSessionScript sessionName;
          };
      in {
        devShells.default = let
          dpanelScripts = mkServiceScripts dpanel;
          dogeboxdScripts = mkServiceScripts dogeboxd;
        in pkgs.mkShell {
          inputsFrom = [
            dogeboxd.devShells.${system}.default
            dkm.devShells.${system}.default
            dpanel.devShells.${system}.default
          ];

          packages = [
            pkgs.git
            upScript
            setupScript
          ]
            ++ (builtins.attrValues dpanelScripts)
            ++ (builtins.attrValues dogeboxdScripts)
          ;
        };

        apps = {
          setup = {
            type = "app";
            program = "${setupScript}/bin/dbx-setup";
          };
        };
      }
    );
}
