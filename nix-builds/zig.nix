{
    stdenv,
    fetchurl,
    ...
}: stdenv.mkDerivation {
    pname = "zig";
    version = "0.12";

    src = fetchurl {
        url = "https://ziglang.org/builds/zig-linux-x86_64-0.12.0-dev.2197+bd4641041.tar.xz";
        sha256 = "sha256-o4ofNC1OEujpjk6eqnrc4DmuV/ATj9EK6RT/hGveqO4";
    };

    installPhase = ''
        mkdir -p $out/bin
        cp zig $out/bin/
        cp -r doc $out/bin/
        cp -r lib $out/bin/
    '';
}
