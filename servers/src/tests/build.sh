ls test_*.pas | xargs -n 1 basename -s .pas | tr '\n' ',' > tests.inc
mkdir -p data/temp
MAIN="testsuite" MODE="DEBUG" SRC="../" PATHS="-Fu../common/ -Futests/" DEFINES="-dTESTSUITE" TESTCMD="true" ../lib/compile.sh || exit 1
(cd ../login-server; NORUN=1 DEFINES="-dTESTSUITE" ./build.sh) || exit 1
(cd ../dynasties-server; NORUN=1 DEFINES="-dTESTSUITE" ./build.sh) || exit 1
(cd ../systems-server; NORUN=1 DEFINES="-dTESTSUITE" ./build.sh) || exit 1
(cd ../..; bin/testsuite) || exit 1
