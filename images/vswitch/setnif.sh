#!/usr/bin/env bash

# Build lib
build()
{
	gcc -o $SO -nostartfiles -fpic -shared -xc - -ldl -D_GNU_SOURCE <<EOF
#include <sys/socket.h>
#include <sys/types.h>
#include <sys/ioctl.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <net/if.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <unistd.h>

int (*std_socket)( int, int, int );
int (*std_bind)( int, const struct sockaddr *, socklen_t addrlen);

void _init( void )
{
	const char *err;

	std_socket = dlsym( RTLD_NEXT, "socket" );
	if( (err = dlerror()) != NULL )
		fprintf( stderr, "dlsym (socket): %s\n", err );

	std_bind = dlsym( RTLD_NEXT, "bind" );
	if( (err = dlerror()) != NULL )
		fprintf( stderr, "dlsym (socket): %s\n", err );
}

static void set_nif( int sockfd )
{
	struct ifreq ifr;
	const char *nif;

	if( !(nif = getenv( "NIF" )) )
	{
		fprintf( stderr, "NIF unset\n" );
		return;
	}

	fprintf( stderr, "PID=%d: Setting NIF=%s for socket=%d\n",
	  getpid(), nif, sockfd );

	memset( &ifr, 0, sizeof( ifr ) );
	strncat( ifr.ifr_name, nif, sizeof( ifr.ifr_name ) );

	if( ioctl( sockfd, SIOCGIFINDEX, &ifr ) )
	{
		perror( "ioctl" );
		return;
	}

	if( setsockopt(
		sockfd,
		SOL_SOCKET,
		SO_BINDTODEVICE,
		(void *)&ifr,
		sizeof( ifr ) ) < 0 )
		perror( "SO_BINDTODEVICE failed" );
}

int socket( int domain, int type, int protocol )
{
	int sockfd;

  sockfd = std_socket( domain, type, protocol );
  fprintf( stderr, "PID=%d: Created socket=%d, domain=%d, type=%d, protocol=%d\n",
	    getpid(), sockfd, domain, type, protocol );
	if( sockfd > 2 && domain == AF_INET )
	{
		set_nif( sockfd );
	}

	return sockfd;
}

int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen)
{
  if( addr->sa_family == AF_INET )
  {
    struct sockaddr_in *addr_in = (struct sockaddr_in *)addr;
    char *sin_addr = inet_ntoa(addr_in->sin_addr);
  	fprintf( stderr, "PID=%d: Binding socket=%d to AF_INET addr %s\n",
	    getpid(), sockfd, sin_addr );
	}
  return std_bind( sockfd, addr, addrlen );
}

EOF
}

(( $# < 2 )) && {
	echo "usage: ${0##*/} DEVICE BINARY [ARGS]"
	exit 1
}

readonly SO=${SO:-"${0%/*}/setnif.so"}

if ! [ -r $SO ] || find ${SO%/*} -newer $SO -name ${0##*/} &>/dev/null
then
	build || exit 1
fi

export NIF=$1
shift

LD_PRELOAD=$SO $@
