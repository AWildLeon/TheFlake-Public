# Host discovery and machine configuration logic
_:
let

  # machineDir and top-level machine groups
  machineDir = ../machines;
  machineToplevels = builtins.attrNames (builtins.readDir machineDir);

  # Find a nested machine configuration: search ./machines/<group>/<host>/configuration.nix
  # or ./machines/<group>/<subgroup>/<host>/configuration.nix
  machineConfig = host:
    let
      # Search in each top-level directory
      search = builtins.foldl'
        (acc: dir:
          if acc != null then acc else
          let
            # Try direct path first
            directPath = toString machineDir + "/" + dir + "/" + host + "/configuration.nix";
          in
          if builtins.pathExists directPath then directPath else
            # Try nested path (for customer/* structure)
          let
            dirPath = toString machineDir + "/" + dir;
            subDirs = builtins.attrNames (builtins.readDir dirPath);
            nestedPath = builtins.foldl'
              (nestedAcc: subDir:
                if nestedAcc != null then nestedAcc else
                let p = dirPath + "/" + subDir + "/" + host + "/configuration.nix"; in
                if builtins.pathExists p then p else null
              )
              null
              subDirs;
          in
          nestedPath
        )
        null
        machineToplevels;
    in
    if search != null then search else toString machineDir + "/" + host + "/configuration.nix";

  # Discover all hostnames under machines/*/<host>/ - handle nested directories
  hosts = builtins.foldl'
    (acc: dir:
      let
        dirPath = toString machineDir + "/" + dir;
        children = builtins.attrNames (builtins.readDir dirPath);
        # For each child, check if it's a machine (has configuration.nix) or needs deeper search
        machines = builtins.foldl'
          (childAcc: child:
            let
              childPath = dirPath + "/" + child;
              configPath = childPath + "/configuration.nix";
              hasConfig = builtins.pathExists configPath;
              # If no direct config, search one level deeper
              subChildren = if hasConfig then [ ] else
              let subDirs = builtins.readDir childPath; in
              builtins.filter (sub: builtins.pathExists (childPath + "/" + sub + "/configuration.nix"))
                (builtins.attrNames subDirs);
            in
            if hasConfig then childAcc ++ [ child ]
            else childAcc ++ subChildren
          ) [ ]
          children;
      in
      acc ++ machines
    ) [ ]
    machineToplevels;

  # Load vars.nix for each host if it exists, with defaults
  loadHostVars = host:
    let
      configPath = machineConfig host;
      hostDir = builtins.dirOf configPath;
      varsPath = hostDir + "/vars.nix";
      hasVars = builtins.pathExists varsPath;
      vars = if hasVars then import varsPath else { };
      # Default deployment settings
      defaultDeployment = {
        targetHost = host;
        targetPort = 22;
        targetUser = "root";
        tags = [ "server" ];
      };
    in
    vars // {
      deployment = defaultDeployment // (vars.deployment or { });
    };

in
{
  inherit
    machineConfig
    hosts
    loadHostVars;
}
