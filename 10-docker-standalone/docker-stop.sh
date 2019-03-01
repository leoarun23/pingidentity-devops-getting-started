#!/usr/bin/env sh
CMD="${0}"
CONTAINER="${1}"
# shellcheck disable=2164
CONTAINER_DIR=$(cd "$( dirname "${0}" )";pwd )
# shellcheck disable=2164
SHARED_DIR=$( cd FF-shared;pwd )

usage ()
{
cat <<EO_USAGE

Usage: ${CMD} { container name }
       container_name: pingdirectory
                       pingfederate
                       pingaccess
                       pingdataconsole
                       all - runs all containers

Examples

  Stop a standalone PingDirectory container

    ${CMD} pingdirectory

  Stop all containers

    ${CMD} all

EO_USAGE
}

run_cmd () {
        INSTANCE=$1

        echo "Running ${CMD} ${INSTANCE}..."
        ${CMD} ${INSTANCE}
}

case ${CONTAINER} in
	"pingdirectory")
		CONTAINER_DIR="${CONTAINER_DIR}/01-pingdirectory"
		;;
	"pingfederate")
		CONTAINER_DIR="${CONTAINER_DIR}/02-pingfederate"
		;;
	"pingaccess")
		CONTAINER_DIR="${CONTAINER_DIR}/03-pingaccess"
		;;
	"pingdataconsole")
		CONTAINER_DIR="${CONTAINER_DIR}/10-pingdataconsole"
		;;
	"all")
		run_cmd pingdirectory
		run_cmd pingfederate
		run_cmd pingaccess
		run_cmd pingdataconsole
		;;
	*)
		usage
		exit
esac

# load the shared variables
# shellcheck source=FF-shared/env_vars
test -f "${SHARED_DIR}/env_vars" && . "${SHARED_DIR}/env_vars"

# load the pingdirectory variables
# shellcheck source=/dev/null
test -f "${CONTAINER_DIR}/env_vars" && . "${CONTAINER_DIR}/env_vars"

# shellcheck disable=2086
if ! test -z "$(docker container ls -a --filter name=${CONTAINER_NAME} -q)" ; then 
    docker container rm ${CONTAINER_NAME} -f
fi

# shellcheck disable=2086
if ! test -z "$(docker container ls --filter name=${CONTAINER_NAME} -q)" ; then 
    docker container stop ${CONTAINER_NAME}
fi
