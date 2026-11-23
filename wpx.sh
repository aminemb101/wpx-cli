#!/bin/bash
COMMAND=$1
shift

case  $COMMAND in
	create)
		./commands/create.sh $@
	;;
	*)
	  echo "unknow command"
	;;
esac

