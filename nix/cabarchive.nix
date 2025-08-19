{
  buildPythonPackage,
  fetchPypi,
}:
buildPythonPackage rec {
  pname = "cabarchive";
  version = "0.2.4";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-BPYAiUcxFM8m6rK34dCWEcW/r47dMgLazvZrtcceSM8=";
  };

  pythonImportsCheck = [ "cabarchive" ];
}
