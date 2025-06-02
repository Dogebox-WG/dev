{
  description = "Unified dev environment for the Dogebox";

  inputs = {
    nixpkgs.url = "nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";

    dpanel = {
      url = "github:dogebox-wg/dpanel";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    dogeboxd = {
      url = "github:dogebox-wg/dogeboxd";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
      inputs.dpanel-src.follows = "dpanel";
    };

    dkm = {
      url = "github:dogebox-wg/dkm";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };
  };

  outputs = { self, nixpkgs, flake-utils, dogeboxd, dkm, dpanel, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        upScript = pkgs.writeShellScriptBin "up" (builtins.readFile ./scripts/up.sh);
        downScript = pkgs.writeShellScriptBin "down" (builtins.readFile ./scripts/down.sh);
        restartScript = pkgs.writeShellScriptBin "r" (builtins.readFile ./scripts/restart.sh);
        setupScript = pkgs.writeShellScriptBin "setup" (builtins.readFile ./scripts/setup.sh);

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
          dkmScripts = mkServiceScripts dkm;
        in pkgs.mkShell {
          inputsFrom = [
            dogeboxd.devShells.${system}.default
            dkm.devShells.${system}.default
            dpanel.devShells.${system}.default
          ];

          packages = [
            pkgs.git
            pkgs.screen
            upScript
            downScript
            restartScript
            setupScript
          ]
            ++ (builtins.attrValues dpanelScripts)
            ++ (builtins.attrValues dogeboxdScripts)
            ++ (builtins.attrValues dkmScripts)
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
