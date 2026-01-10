ls test_*.pas | xargs -n 1 basename -s .pas | sort | tr '\n' ',' > tests.inc
# add -aL to the DEFINES to get assembler files
MAIN="testsuite" MODE="DEBUG" SRC="../" PATHS="-Fu../common/ -Futests/" BIN="../../bin-tests/" DEFINES="-dTESTSUITE" NORUN=1 ../lib/compile.sh || exit 1
(cd ../login-server; NORUN=1 BIN="../../bin-tests/" DEFINES="-dTESTSUITE" ./build.sh) || exit 1
(cd ../dynasties-server; NORUN=1 BIN="../../bin-tests/" DEFINES="-dTESTSUITE" ./build.sh) || exit 1
(cd ../systems-server; NORUN=1 BIN="../../bin-tests/" DEFINES="-dTESTSUITE" ./build.sh) || exit 1
(cd ../..; bin-tests/testsuite) || exit 1
