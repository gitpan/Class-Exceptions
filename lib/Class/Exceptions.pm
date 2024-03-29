package Class::Exceptions;

use 5.005;

use strict;
use vars qw($VERSION $BASE_EXC_CLASS %CLASSES);

BEGIN { $BASE_EXC_CLASS ||= 'BaseException'; }

$VERSION = '0.5';

sub import
{
    my $class = shift;

    my %needs_parent;
 MAKE_CLASSES:
    while (my $subclass = shift)
    {
	my $def = ref $_[0] ? shift : {};
	$def->{isa} = $def->{isa} ? ( ref $def->{isa} ? $def->{isa} : [$def->{isa}] ) : [];

	# We already made this one.
	next if $CLASSES{$subclass};

	{
	    no strict 'refs';
	    foreach my $parent (@{ $def->{isa} })
	    {
		unless ( defined ${"$parent\::VERSION"} || @{"$parent\::ISA"} )
		{
		    $needs_parent{$subclass} = { parents => $def->{isa},
						 def => $def };
		    next MAKE_CLASSES;
		}
	    }
	}

	$class->_make_subclass( subclass => $subclass,
				def => $def || {} );
    }

    foreach my $subclass (keys %needs_parent)
    {
	# This will be used to spot circular references.
	my %seen;
	$class->_make_parents( \%needs_parent, $subclass, \%seen );
    }
}

sub _make_parents
{
    my $class = shift;
    my $h = shift;
    my $subclass = shift;
    my $seen = shift;
    my $child = shift; # Just for error messages.

    no strict 'refs';

    # What if someone makes a typo in specifying their 'isa' param?
    # This should catch it.  Either it's been made because it didn't
    # have missing parents OR it's in our hash as needing a parent.
    # If neither of these is true then the _only_ place it is
    # mentioned is in the 'isa' param for some other class, which is
    # not a good enough reason to make a new class.
    die "Class $subclass appears to be a typo as it is only specified in the 'isa' param for $child\n"
	unless exists $h->{$subclass} || $CLASSES{$subclass} || @{"$subclass\::ISA"};

    foreach my $c ( @{ $h->{$subclass}{parents} } )
    {
	# It's been made
	next if $CLASSES{$c} || @{"$c\::ISA"};

	die "There appears to be some circularity involving $subclass\n"
	    if $seen->{$subclass};

	$seen->{$subclass} = 1;

	$class->_make_parents( $h, $c, $seen, $subclass );
    }

    return if $CLASSES{$subclass} || @{"$subclass\::ISA"};

    $class->_make_subclass( subclass => $subclass,
			    def => $h->{$subclass}{def} );
}

sub _make_subclass
{
    my $class = shift;
    my %p = @_;

    my $subclass = $p{subclass};
    my $def = $p{def};

    my $isa;
    if ($def->{isa})
    {
	$isa = ref $def->{isa} ? join ' ', @{ $def->{isa} } : $def->{isa};
    }
    $isa ||= $BASE_EXC_CLASS;

    my $code = <<"EOPERL";
package $subclass;

use vars qw(\$VERSION \$DO_TRACE);

use base qw($isa);

\$VERSION = '1.0';

\$DO_TRACE = 0;

1;

EOPERL


    if ($def->{description})
    {
	$code .= <<"EOPERL";
sub description
{
    return '$def->{description}';
}
EOPERL
    }

    eval $code;

    die $@ if $@;

    $CLASSES{$subclass} = 1;
}

package BaseException;

use StackTrace;

use fields qw( error pid uid euid gid egid time trace );

use overload
    '""' => \&as_string,
    fallback => 1;

use vars qw($VERSION $DO_TRACE);

$VERSION = '0.5';

$DO_TRACE = 0;

# Create accessor routines
BEGIN
{
    no strict 'refs';
    foreach my $f (keys %{__PACKAGE__ . '::FIELDS'})
    {
	*{$f} = sub { my BaseException $s = shift; return $s->{$f}; };
    }
}

1;

sub throw
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    die $class->new(@_);
}

sub rethrow
{
    my BaseException $self = shift;

    die $self;
}

sub new
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    my $self;
    {
	no strict 'refs';
	$self = bless [ \%{"${class}::FIELDS"} ], $class;
    }

    $self->_initialize(@_);

    return $self;
}

sub _initialize
{
    my BaseException $self = shift;
    my %p = @_;

    # Try to get something useful in there (I hope).
    $self->{error} = $p{error} || $!;

    $self->{time} = CORE::time; # with CORE:: sometimes makes a warning (why?)
    $self->{pid}  = $$;
    $self->{uid}  = $<;
    $self->{euid} = $>;
    $self->{gid}  = $(;
    $self->{egid} = $);

    if ($self->do_trace)
    {
	$self->{trace} = StackTrace->new( ignore_class => __PACKAGE__ );
    }
}

sub description
{
    return 'Generic exception';
}

sub do_trace
{
    my $proto = shift;
    my $class = ref $proto || $proto;

    {
	no strict 'refs';
	if ( defined ( my $val = shift ) )
	{
	    ${"$class\::DO_TRACE"} = $val;
	}

	return ${"$class\::DO_TRACE"};
    }
}

sub as_string
{
    my BaseException $self = shift;

    my $str = $self->{error};
    if ($self->trace)
    {
	$str .= "\n\n" . $self->trace->as_string;
    }

    return $str;
}

__END__

=head1 NAME

Class::Exceptions - A module that allows you to declare real exception
classes in Perl

=head1 SYNOPSIS

  use Class::Exceptions (
                  'MyException',
                  'AnotherException' => { isa => 'MyException' },
                  'YetAnotherException' => { isa => 'AnotherException',
                                             description => 'These exceptions are related to IPC' }                        );

  eval { MyException->throw( error => 'I feel funny.'; };

  print $@->error, "\n";

  MyException->trace(1);
  eval { MyException->throw( error => 'I feel funnier.'; };

  print $@->error, "\n", $@->trace->as_string, "\n";
  print join ' ',  $@->euid, $@->egid, $@->uid, $@->gid, $@->pid, $@->time;

  # catch
  if ($@->isa('MyException'))
  {
     do_something();
  }
  elsif ($@->isa('FooException'))
  {
     go_foo_yourself();
  }
  else
  {
     $@->rethrow;
  }

=head1 DESCRIPTION

Class::Exceptions allows you to declare exceptions in your modules in
a manner similar to how exceptions are declared in Java.

It features a simple interface allowing programmers to 'declare'
exception classes at compile time.  It also has a base exception
class, BaseException, that can be used for classes stored in files
(aka modules ;) ) that are subclasses.

It is designed to make structured exception handling simpler and
better by encouraging people to use hierarchies of exceptions in their
applications.

=head1 DECLARING EXCEPTION CLASSES

The 'use Class::Exceptions' syntax lets you automagically create the
relevant BaseException subclasses.  You can also create subclasses via
the traditional means of external modules loaded via 'use'.  These two
methods may be combined.

The syntax for the magic declarations is as follows:

'MANDATORY CLASS NAME' => \%optional_hashref

The hashref may contain two options:

=over 4

=item * isa

This is the class's parent class.  If this isn't provided then the
class name is $Class::Exceptions::BASE_EXC_CLASS is assumed to be the
parent (see below).

This parameter lets you create arbitrarily deep class hierarchies.
This can be any other BaseException subclass in your declaration _or_
a subclass loaded from a module.

To change the default exception class you will need to change the
value of $Class::Exceptions::BASE_EXC_CLASS _before_ calling
C<import>.  To do this simply do something like this:

BEGIN { $Class::Exceptions::BASE_EXC_CLASS = 'SomeExceptionClass'; }

If anyone can come up with a more elegant way to do this please let me
know.

CAVEAT: If you want to automagically subclass a BaseException class
loaded from a file, then you _must_ compile the class (via use or
require or some other magic) _before_ you do 'use Class::Exceptions'
or you'll get a compile time error.  This may change with the advent
of Perl 5.6's CHECK blocks, which could allow even more crazy
automagicalness (which may or may not be a good thing).

=item * description

Each exception class has a description method that returns a fixed
string.  This should describe the exception _class_ (as opposed to the
particular exception being thrown).  This is useful for debugging if
you start catching exceptions you weren't expecting (particularly if
someone forgot to document them) and you don't understand the error
messages.

=back

The Class::Exceptions magic attempts to detect circular class
hierarchies and will die if it finds one.  It also detects missing
links in a chain so if you declare Bar to be a subclass of Foo and
never declare Foo then it will also die.  My tests indicate that this
is functioning properly but this functionality is still somewhat
experimental.

=head1 BaseException CLASS METHODS

=over 4

=item * do_trace($true_or_false)

Each BaseException subclass can be set individually to make a
StackTrace object when an exception is thrown.  The default is to not
make a trace.  Calling this method with a value changes this behavior.
It always returns the current value (after any change is applied).

=item * throw( error => $error_message )

This method creates a new BaseException object with the given error
message.  If no error message is given, $! is used.  It then die's
with this object as its argument.

=item * new( error => $error_message )

Returns a new BaseException object with the given error message.  If
no error message is given, $! is used.

=item * description

Returns the description for the given BaseException subclass.  The
BaseException class's description is 'Generic exception' (this may
change in the future).  This is also an object method.

=back

=head1 BaseException OBJECT METHODS

=over 4

=item * rethrow

Simply dies with the object as its sole argument.  It's just syntactic
sugar.  This does not change any of the object's attribute values.
However, it will cause C<caller> to report the die as coming from
within the BaseException class rather than where rethrow was called.

=item * error

Returns the error message associated with the exception.

=item * pid

Returns the pid at the time the exception was thrown.

=item * uid

Returns the real user id at the time the exception was thrown.

=item * gid

Returns the real group id at the time the exception was thrown.

=item * euid

Returns the effective user id at the time the exception was thrown.

=item * egid

Returns the effective group id at the time the exception was thrown.

=item * time

Returns the time in seconds since the epoch at the time the exception
was thrown.

=item * trace

Returns the trace object associated with the BaseException if do_trace
was true at the time it was created or undef.

=item * as_string

Returns a string form of the error message (something like what you'd
expect from die).  If there is a trace available then it also returns
this in string form (like confess).

=back

=head1 OVERLOADING

The BaseException object is overloaded so that stringification
produces a normal error message.  It just calls the as_string method
described above.  This means that you can just C<print $@> after an
eval and not worry about whether or not its an actual object.  It also
means an application or module could do this:

 $SIG{__DIE__} = sub { BaseException->throw( error => join '', @_ ); };

and this would probably not break anything (unless someone was
expecting a different type of exception object from C<die>).

=head1 USAGE RECOMMENDATION

If you're creating a complex system that throws lots of different
types of exceptions consider putting all the exception declarations in
one place.  For an app called Foo you might make a Foo::Exceptions
module and use that in all your code.  This module could just contain
the code to make Class::Exceptions do its automagic class creation.
This allows you to more easily see what exceptions you have and makes
it easier to keep track of them all (as opposed to looking at the top
of 10-20 different files).  It's also ever so slightly faster as the
Class::Exception->import method doesn't get called over and over again
(though a given class is only ever made once).

You may want to create a real module to subclass BaseException as
well, particularly if you want your exceptions to have more methods.
Read the L<DECLARING EXCEPTION CLASSES> section for more details.

=head1 AUTHOR

Dave Rolsky, <autarch@urth.org>

=head1 SEE ALSO

StackTrace

=cut
