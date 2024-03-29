# Before `make install' is performed this script should be runnable with
# `make test'. After `make install' it should work as `perl test.pl'

######################### We start with some black magic to print on failure.

# Change 1..1 below to 1..last_test_to_print .
# (It may become useful if the test is moved to ./t subdirectory.)

BEGIN { $| = 1; print "1..20\n"; }
END {print "not ok 1\n" unless $main::loaded;}

# There's actually a few tests here of the import routine.  I don't
# really know how to quantify them though.  If test.pl fails to
# compile and there's an error from the BaseException class then something
# here failed.
BEGIN
{
    package FooException;

    use vars qw[$VERSION];

    use Class::Exceptions;
    use base qw(BaseException);

    $VERSION = 0.01;

    1;
}

use Class::Exceptions ( 'YAE' => { isa => 'SubTestException' },
			'SubTestException' => { isa => 'TestException',
						description => 'blah blah' },
			'TestException',
			'FooBarException' => { isa => 'FooException' },
		      );


$Class::Exceptions::BASE_EXC_CLASS = 'FooException';
Class::Exceptions->import( 'BlahBlah' );

use strict;

$^W = 1;
$main::loaded = 1;

result( $main::loaded, "Unable to load Class::Exceptions module\n" );

# 2-5: Accessors
{
    eval { BaseException->throw( error => 'err' ); };

    result( $@->isa('BaseException'),
	    "\$\@ is not an BaseException\n" );

    result( $@->error eq 'err',
	    "Exception's error message should be 'err' but it's '", $@->error, "'\n" );

    result( $@->description eq 'Generic exception',
	    "Description should be 'Generic exception' but it's '", $@->description, "'\n" );

    result( ! defined $@->trace,
	    "Exception object has a stacktrace but it shouldn't\n" );
}

# 6-14 : Test subclass creation
{
    eval { TestException->throw( error => 'err' ); };

    result( $@->isa( 'TestException' ),
	    "TestException was thrown in class ", ref $@, "\n" );

    result( $@->description eq 'Generic exception',
	    "Description should be 'Generic exception' but it's '", $@->description, "'\n" );

    eval { SubTestException->throw( error => 'err' ); };

    result( $@->isa( 'SubTestException' ),
	    "SubTestException was thrown in class ", ref $@, "\n" );

    result( $@->isa( 'TestException' ),
	    "SubTestException should be a subclass of TestException\n" );

    result( $@->isa( 'BaseException' ),
	    "SubTestException should be a subclass of BaseException\n" );

    result( $@->description eq 'blah blah',
	    "Description should be 'blah blah' but it's '", $@->description, "'\n" );

    eval { YAE->throw( error => 'err' ); };

    result( $@->isa( 'SubTestException' ),
	    "YAE should be a subclass of SubTestException\n" );

    eval { BlahBlah->throw( error => 'yadda yadda' ); };
    result( $@->isa('FooException'),
	    "The BlahBlah class should be a subclass of FooException\n" );
    result( $@->isa('BaseException'),
	    "The BlahBlah class should be a subclass of BaseException\n" );
}


# 15-18 : Trace related tests
{
    result( BaseException->do_trace == 0,
	    "BaseException class 'do_trace' method should return false\n" );

    BaseException->do_trace(1);

    result( BaseException->do_trace == 1,
	    "BaseException class 'do_trace' method should return false\n" );

    eval { argh(); };

    result( $@->trace->as_string,
	    "Exception should have a stack trace\n" );

    my @f;
    while ( my $f = $@->trace->next_frame ) { push @f, $f; }

    result( ( ! grep { $_->package eq 'BaseException' } @f ),
	    "Trace contains frames from BaseException package\n" );
}

# 19-20 : overloading
{
    BaseException->do_trace(0);
    eval { BaseException->throw( error => 'overloaded' ); };

    result( "$@" eq 'overloaded', "Overloading is not working\n" );

    BaseException->do_trace(1);
    eval { BaseException->throw( error => 'overloaded again' ); };
    my $x = "$@" =~ /overloaded again.+eval {...}\('BaseException', 'error', 'overloaded again'\)/s;
    result( $x, "Overloaded stringification did not include the expected stack trace\n" );
}

sub argh
{
    BaseException->throw( error => 'ARGH' );
}

sub result
{
    my $ok = !!shift;
    use vars qw($TESTNUM);
    $TESTNUM++;
    print "not "x!$ok, "ok $TESTNUM\n";
    print @_ if !$ok;
}
