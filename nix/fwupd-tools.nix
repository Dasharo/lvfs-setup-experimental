{
  lib,
  runtimeShell,
  buildPythonApplication,
  libjcat,
  fwupd,
  openssl,
  lxml,
  cabarchive,
}:
buildPythonApplication {
  name = "fwupd-tools";
  dontUnpack = true;
  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin
    install -m 0755 ${../tools/mkupdate.sh} $out/bin/mkupdate
    substituteInPlace $out/bin/mkupdate \
      --replace-fail '#!/usr/bin/env bash' '#!${runtimeShell}' \
      --replace-fail '# _jcat_cmd=""' '_jcat_cmd="${lib.getExe libjcat.bin}"' \
      --replace-fail '_fwupdtool=fwupdtool' '_fwupdtool="${fwupd.out}/bin/fwupdtool"'

    install -m 0755 ${../tools/mktestkey.sh} $out/bin/mktestkey
    substituteInPlace $out/bin/mktestkey \
      --replace-fail '#!/usr/bin/env bash' '#!${runtimeShell}' \
      --replace-fail '_openssl=openssl' '_openssl="${lib.getExe openssl}"'

    install -m 0755 ${../tools/build_fwstore.py} $out/bin/build_fwstore
    substituteInPlace $out/bin/build_fwstore \
      --replace-fail 'JCAT_PATH = None' 'JCAT_PATH = "${lib.getExe libjcat.bin}"'

    runHook postInstall
  '';
  dontUseSetuptoolsBuild = true;
  format = "other";
  propagatedBuildInputs = [
    lxml
    cabarchive
  ];
}
