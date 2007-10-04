use warnings;
use strict;

=head1 NAME

Jifty::Model::ModelClass - Tracks Jifty-related metadata

=head1 SYNOPSIS


=head1 DESCRIPTION

Every Jifty application automatically inherits this table, which
describes information about Jifty models which are stored only in the
database.  It uses this information to construct new model classes on
the fly as they're required by the application.

=cut

package Jifty::Model::ModelClass;
use base qw( Jifty::Record );
use Scalar::Defer;

use Jifty::DBI::Schema;
use Jifty::Record schema {
    column name => 
        type is 'text',
        label is 'Model name',
        is distinct,
        is mandatory,
        is immutable;
    column description => 
        type is 'text',
        label is 'Description',
        render_as 'Textarea'; 
    column super_classes =>
        type is 'text',
        label is 'Super classes',
        hints is 'A space separated list of classes from which this model will inherit.',
        validator is \&validate_super_classes;
    column mixin_classes =>
        type is 'text',
        label is 'Mixin classes',
        hints is 'A space separated list of mixin classes to load into this object.',
        validator is \&validate_super_classes;
    column included_columns => 
        refers_to Jifty::Model::ModelClassColumnCollection by 'model_class';
};

use Hash::Merge ();

=head2 table

Database-backed models are stored in the table C<_jifty_models>.

=cut

sub table {'_jifty_models'}

=head2 since

The metadata table first appeared in Jifty version 0.70127

=cut

sub since {'0.70127'}


=head2 after_create

After create, instantiate our new class and create its database schema.

=cut


sub after_create {
    my $self = shift;
    my $idref = shift;
    $self->load_by_cols(id => $$idref);
    $self->instantiate();
    $self->qualified_class->create_table_in_db();
    return 1;
}


=head2 delete

When deleting model classes from the metamodel tables, we also drop the table in the database.

=cut

sub delete {
    my $self = shift;
    # XXX TODO: remove all columns here.
    $self->qualified_class->drop_table_in_db();
    return $self->SUPER::delete(@_);
}


=head2 qualified_class

Returns the fully qualified class name of the model class described the current ModelClass object.

=cut

sub qualified_class {
    my $self = shift;
    my $fully_qualified_class = Jifty->app_class('Model', $self->name);
    return $fully_qualified_class; 
}

=head2 instantiate 

For the currently loaded ModelClass object, loads up all its columns and
creates a model class definition and evals it into existence. Basically,
you call this method to create a live model class. It should probably
only be called by the Jifty classloader.

=cut

sub instantiate {
    my $self = shift;
    $self->_instantiate_stub_class;
    $self->qualified_class->_init_columns();
    my $cols = $self->included_columns;
    while (my $col = $cols->next) {
        $self->add_column($col);
    }
    return 1;
}

=head2 add_column

Create an in-memory column definition for a column object.

=cut

sub add_column {
    my $self = shift;
    my $col = shift;
    my $column =$self->qualified_class->add_column($col->name);

    if ($col->type_handler) {
        my $name = $col->name;
        my $typehandler = $col->type_handler;

        # TODO XXX FIXME There has got to be a better way. Someone who knows
        # the guts of Jifty::DBI::Schema and Object::Declare can probably clean
        # this up.

        package Jifty::DBI::Schema;
        my $type_handler_column 
            = &declare(sub { column $name => is $typehandler })->{$name};
        %$column = %{ Hash::Merge::merge($column, $type_handler_column) };
    }

    for (qw(readable writable hints indexed max_length render_as mandatory sort_order virtual)) {
        $column->$_( $col->$_() ) if $col->$_();
    }

    $column->label( $col->label_text ) if $col->label_text;

    $column->refers_to( $col->refers_to_class ) if $col->refers_to_class;
    $column->by( $col->refers_to_by ) if $col->refers_to_by;

    $column->default( $col->default_value );
    $column->distinct( $col->distinct_value ) if $col->distinct_value;
    $column->type( $col->storage_type ) if $col->storage_type;

    if (my $handler = $column->attributes->{'_init_handler'}) {
        $handler->($column, $self->qualified_class);
    }

    $self->qualified_class->_init_methods_for_column($column);
}


sub _instantiate_stub_class {
    my $self = shift;
    my $fully_qualified_class = $self->qualified_class();
    my $path =  join('/', split(/::/,$fully_qualified_class)).".pm"; 
    return if ($INC{$path});

    my $uuid = $self->__uuid;
    my $base_class = Jifty->config->framework('ApplicationClass') . "::Record";
    my $super_classes 
        = defined $self->super_classes ? $self->super_classes.' ' : '';
    my $mixin_classes
        = join "\n",
          map  { "use $_;" }
               defined $self->mixin_classes 
                   ? split /\s+/, $self->mixin_classes : ();

    my $class                 = << "EOF";
use warnings;
use strict;
package $fully_qualified_class;
use base qw'$super_classes$base_class';

use constant CLASS_UUID => '$uuid';

use Jifty::DBI::Schema;
use $base_class schema {
};

$mixin_classes

sub _autogenerated {1}
1;

EOF

    local $@;
    eval "$class";
    # Fake out the classloader so that it doesn't try to autoload our magically blessed-into-existence class
    # This WILL hurt us when you also want an on-disk version of the same.
    # At that point, the instantiation of db-backed classes should move into the classloader
    if ($@) { die $@; }
    $INC{$path} = '#autoloaded';

    # Cause the new record's collection to be auto-generated by the ClassLoader
    # to make it appear magically with record.
    eval "use ${fully_qualified_class}Collection";
    if ($@) { die $@; }
}

=head2 validate_super_classes

Makes certain that the value is a list of space separated class names.

=cut

my $list_of_packages = qr/^
    \s* (?: \w+ ) (?: :: \w+ )*          # match the first
    ( \s+ (?: \w+ ) (?: :: \w+ )* )* \s* # match the rest
$/x;

sub validate_super_classes {
    my ($self, $value) = @_;
    my $ret = Class::ReturnValue->new;

    if ($value =~ /^$/ || $value =~ $list_of_packages) {
        $ret->as_array(1, 'OK');
    }

    else {
        $ret->as_array(0, 'This must be a space separated list of Perl class names.');
        $ret->as_error(
            errno        => 1,
            do_backtrace => 0,
            message      => 'This must be a space separated list of class names.',
        );
    }

    return $ret->return_value;
}

1;
