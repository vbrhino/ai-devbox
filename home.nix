{ config, lib, pkgs, username ? builtins.getEnv "USER", homeDirectory ? builtins.getEnv "HOME", ... }:

{
  home.username      = if username != "" then username else "user";
  home.homeDirectory = if homeDirectory != "" then homeDirectory else "/home/user";
  home.stateVersion  = "24.11";

  programs.home-manager.enable = true;

  # ════════════════════════════════════════════════════════════════════════
  #  Packages
  # ════════════════════════════════════════════════════════════════════════
  home.packages = with pkgs; [

    # ── Core CLI ────────────────────────────────────────────────────────
    curl
    wget
    gnupg
    openssh
    jq
    yq-go
    tmux
    vim
    nano
    tree

    # ── Modern CLI replacements ─────────────────────────────────────────
    ripgrep
    fd
    eza
    sd
    procs
    dust
    duf
    bat
    difftastic
    tldr
    htop
    btop
    watch
    btop

    # ── Build toolchain ─────────────────────────────────────────────────
    gcc
    gnumake
    binutils
    pkg-config
    cmake

    # ── Python / Data Science ──────────────────────────────────────────
    python313
    python313Packages.pip
    python313Packages.virtualenv
    python313Packages.pipx
    python313Packages.numpy
    python313Packages.pandas
    python313Packages.matplotlib
    python313Packages.scikit-learn
    python313Packages.jupyterlab
    python313Packages.notebook
    python313Packages.ipython
    uv                      # Fast Python package installer (Rust)

    # ── Node.js / JavaScript ────────────────────────────────────────────
    nodejs_22
    nodePackages.typescript
    nodePackages.prettier

    # ── Go ──────────────────────────────────────────────────────────────
    go

    # ── Docker / Containers ─────────────────────────────────────────────
    docker
    docker-compose
    lazydocker
    dive
    skopeo
    crane

    # ── AI / ML Tools (Nix-managed) ────────────────────────────────────
    aider-chat
    aichat
    mods
    fabric-ai
    shell-gpt
    tgpt
    llama-cpp              # llama.cpp core (will rebuild with HIPBLAS for GPU)

    # ── Git extras ──────────────────────────────────────────────────────
    git
    git-lfs
    gh
    lazygit
    act
    pre-commit

    # ── Networking ──────────────────────────────────────────────────────
    dnsutils
    dog
    nmap
    netcat-gnu
    socat
    tcpdump
    bandwhich
    tailscale

    # ── Observability ───────────────────────────────────────────────────
    prometheus
    grafana-loki
    hey

    # ── API & debugging ─────────────────────────────────────────────────
    grpcurl
    httpie
    xh
    websocat

    # ── Code quality ────────────────────────────────────────────────────
    cloc
    tokei
    yamllint
    shellcheck
    hadolint
    trivy

    # ── ROCm / GPU tools (packages, not kernel drivers) ────────────────
    rocmPackages.rocm-smi
    rocmPackages.rocminfo
    rocmPackages.rocm-bandwidth-test

    # (HIP/ROCm compilation handled post-swap via system packages)

    # ── Terminal eye candy ────────────────────────────────────────────────
    cmatrix
    neofetch
    fastfetch

    # ── Archive / misc ──────────────────────────────────────────────────
    unzip
    zip
    zstd
    xz
    bzip2
    file
    gettext
    openssl
    hwloc                  # CPU topology / NUMA info
    pciutils               # lspci
    usbutils               # lsusb
    dmidecode              # hardware info
    lm_sensors             # temperature monitoring
    smartmontools          # disk health
  ];

  # ════════════════════════════════════════════════════════════════════════
  #  Program configs
  # ════════════════════════════════════════════════════════════════════════

  # ── Zsh + Oh My Zsh ──────────────────────────────────────────────────
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    syntaxHighlighting.enable = true;

    oh-my-zsh = {
      enable = true;
      theme = "";
      plugins = [
        "git"
        "docker"
        "direnv"
        "python"
        "pip"
      ];
    };

    shellAliases = {
      ls   = "eza";
      ll   = "eza -la --git";
      lt   = "eza --tree";
      cat  = "bat --paging=never --plain";
      pps  = "procs";
      du   = "dust";
      df   = "duf";
      ddiff = "difft";
      ssd  = "sd";

      # AI
      ollama-up  = "sudo systemctl start ollama";
      ollama-down = "sudo systemctl stop ollama";
      open-webui = "cd ~/ai-devbox/docker/open-webui && docker compose up -d";

      # System
      status    = "~/status.sh";
      update    = "~/ai-devbox/scripts/update.sh";
      swap      = "sudo ~/ai-devbox/scripts/after-gpu-swap.sh";

      # Docker
      dps  = "docker ps";
      dimg = "docker images";
      dl   = "docker logs -f";

      # GPU
      gpu-info  = "sudo rocm-smi 2>/dev/null || nvidia-smi 2>/dev/null || echo 'no GPU detected'";
      gpu-top   = "watch -n1 'sudo rocm-smi --showuse 2>/dev/null || nvidia-smi --query-gpu=utilization.gpu,memory.used,memory.total --format=csv,noheader'";
    };

    initContent = ''
      # ai-devbox update
      ai-devbox-update() { ~/ai-devbox/scripts/update.sh; exec zsh; }

      # Start in home directory when launched from Windows Terminal
      [[ "$PWD" == /mnt/* ]] && cd ~

      # fzf / zoxide — handled by programs.fzf and programs.zoxide modules

      # Coloured man pages
      export LESS_TERMCAP_mb=$'\e[1;32m'
      export LESS_TERMCAP_md=$'\e[1;32m'
      export LESS_TERMCAP_me=$'\e[0m'
      export LESS_TERMCAP_se=$'\e[0m'
      export LESS_TERMCAP_so=$'\e[01;44;33m'
      export LESS_TERMCAP_ue=$'\e[0m'
      export LESS_TERMCAP_us=$'\e[1;36m'
    '';
  };

  # ── Starship prompt ─────────────────────────────────────────────────
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      command_timeout = 2000;

      format = lib.concatStrings [
        "$directory"
        "$git_branch"
        "$git_status"
        "$python"
        "$nodejs"
        "$golang"
        "$docker_context"
        "$cmd_duration"
        "$time"
        "$line_break"
        "$nix_shell"
        "$character"
      ];

      directory = {
        style             = "fg:#e3e5e5 bg:#769ff0";
        format            = "[ $path ]($style)";
        truncation_length = 3;
        truncation_symbol = ".../";
      };

      git_branch = {
        symbol = "git:";
        style  = "bg:#394260";
        format = "[[ $symbol$branch ](fg:#769ff0 bg:#394260)]($style)";
      };
      git_status = {
        style  = "bg:#394260";
        format = "[[($all_status$ahead_behind )](fg:#769ff0 bg:#394260)]($style)";
      };

      python = {
        symbol = "py:";
        style  = "bg:#212736";
        format = "[[ $symbol$version ](fg:#769ff0 bg:#212736)]($style)";
      };
      nodejs = {
        symbol = "node:";
        style  = "bg:#212736";
        format = "[[ $symbol$version ](fg:#769ff0 bg:#212736)]($style)";
      };
      golang = {
        symbol = "go:";
        style  = "bg:#212736";
        format = "[[ $symbol$version ](fg:#769ff0 bg:#212736)]($style)";
      };

      docker_context = {
        symbol = "docker:";
        style  = "bg:#1a1b26";
        format = "[[ $symbol$context ](fg:#769ff0 bg:#1a1b26)]($style)";
      };

      cmd_duration = {
        min_time = 2000;
        style    = "bg:#1d2230";
        format   = "[[ took $duration ](fg:#a0a9cb bg:#1d2230)]($style)";
      };
      time = {
        disabled    = false;
        time_format = "%R";
        style       = "bg:#1d2230";
        format   = "[[ $time ](fg:#a0a9cb bg:#1d2230)]($style)";
      };

      nix_shell = {
        symbol = "nix ";
        format = "[$symbol]($style) ";
        style  = "bold #769ff0";
      };

      line_break.disabled = false;

      character = {
        success_symbol            = "[❯](bold #9ece6a)";
        error_symbol              = "[❯](bold #f7768e)";
        vimcmd_symbol             = "[❮](bold #9ece6a)";
        vimcmd_replace_one_symbol = "[❮](bold #bb9af7)";
        vimcmd_replace_symbol     = "[❮](bold #bb9af7)";
        vimcmd_visual_symbol      = "[❮](bold #e0af68)";
      };
    };
  };

  # ── Git ───────────────────────────────────────────────────────────────
  programs.git = {
    enable = true;
    settings = {
      init.defaultBranch = "main";
      pull.rebase        = true;
      push.autoSetupRemote = true;
      merge.conflictstyle  = "diff3";
      diff.colorMoved      = "default";
    };
  };

  # ── Delta (git pager) ────────────────────────────────────────────────
  programs.delta = {
    enable = true;
    enableGitIntegration = true;
    options = {
      navigate      = true;
      line-numbers  = true;
      side-by-side  = true;
      syntax-theme  = "Dracula";
    };
  };

  # ── GitHub CLI ────────────────────────────────────────────────────────
  programs.gh = {
    enable = true;
    settings.git_protocol = "ssh";
  };

  # ── lazygit ───────────────────────────────────────────────────────────
  programs.lazygit.enable = true;

  # ── direnv ─────────────────────────────────────────────────────────────
  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  # ── bat ───────────────────────────────────────────────────────────────
  programs.bat = {
    enable = true;
    config = {
      theme = "Dracula";
      style = "numbers,changes,header";
    };
  };

  # ── fzf ──────────────────────────────────────────────────────────────
  programs.fzf = {
    enable = true;
    enableZshIntegration = true;
    defaultOptions = [
      "--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8"
      "--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc"
      "--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8"
      "--border=rounded"
      "--prompt='  '"
      "--pointer=' '"
    ];
  };

  # ── zoxide ──────────────────────────────────────────────────────────
  programs.zoxide = {
    enable = true;
    enableZshIntegration = true;
  };

  # ════════════════════════════════════════════════════════════════════════
  #  Environment variables
  # ════════════════════════════════════════════════════════════════════════
  home.sessionVariables = {
    EDITOR             = "vim";
    PIP_REQUIRE_VIRTUALENV = "false";
    OLLAMA_HOST        = "0.0.0.0";  # Listen on all interfaces
    OLLAMA_NUM_PARALLEL = "1";
    OLLAMA_MAX_LOADED_MODELS = "2";
  };

  home.sessionPath = [
    "$HOME/.local/bin"
    "$HOME/.npm-global/bin"
    "$HOME/ai-devbox/scripts"
  ];

  # ════════════════════════════════════════════════════════════════════════
  #  Systemd user services (auto-start Docker, Ollama via user service)
  # ════════════════════════════════════════════════════════════════════════

  # On a server without systemd (WSL), these are no-ops.
  # On bare-metal Ubuntu, systemd --user manages them.
}
