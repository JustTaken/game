{
    stdenv,
    fetchurl,
    pkg-config,
    cmake,
    ...
}: stdenv.mkDerivation {
    pname = "vulkan-sdk";
    version = "1.3.275.0";

    src = fetchurl {
        url = "https://sdk.lunarg.com/sdk/download/1.3.275.0/linux/vulkansdk-linux-x86_64-1.3.275.0.tar.xz";
        sha256 = "sha256-tkxbdjTn1x4o4+o9C3dSNMvBjOL056AxNBpPn25Gc7U=";
    };
    nativeBuildInputs = [ pkg-config ];

    outputs = [ "out" ];
    installPhase = ''
        mkdir -p $out/include
        mkdir -p $out/lib
        mkdir -p $out/bin
        cp -r x86_64/include/* $out/include
        cp -r x86_64/bin/* $out/bin
        cp -r x86_64/lib/* $out/lib
    '';
}
