use warnings;
use strict;

=head1 NAME

Jifty::Action::Record::Search

=head1 DESCRIPTION

The class is a base class for L<Jifty::Action>s that serve to provide
an interface to general searches through L<Jifty::Record> objects. To
use it, subclass it and override the C<record_class> method to return
the fully qualified name of the model to do searches over.

=cut

package Jifty::Action::Record::Search;
use base qw/Jifty::Action::Record/;

=head1 METHODS

=head2 arguments

Remove validators from arguments, as well as ``mandatory''
restrictions. Remove any arguments that render as password fields, or
refer to collections.

=cut

sub arguments {
    my $self = shift;
    return $self->_cached_arguments if $self->_cached_arguments;
    
    my $args = $self->SUPER::arguments;
    for my $field (keys %$args) {
        
        my $info = $args->{$field};

        my $column = $self->record->column($field);
        # First, modify the ``exact match'' search field (same name as
        # the original argument)

        delete $info->{validator};
        delete $info->{mandatory};

        if($info->{valid_values}) {
            my $valid_values = $info->{valid_values};
            $valid_values = [$valid_values] unless ref($valid_values) eq 'ARRAY';
            unshift @$valid_values, "";
        }
        
        if(lc $info->{'render_as'} eq 'password') {
            delete $args->{$field};
        } 
        if($column && defined(my $refers_to = $column->refers_to)) {
            delete $args->{$field}
             if UNIVERSAL::isa($refers_to, 'Jifty::Collection');
        }
        # XXX TODO: What about booleans? Checkbox doesn't quite work,
        # since there are three choices: yes, no, either.

        # XXX TODO: Create arguments for comparisons and substring
        # matching
    }

    return $self->_cached_arguments($args);
}

=head2 take_action

Return a collection with the result of the search specified by the
given arguments.

We interpret a C<undef> argument as SQL C<NULL>, and ignore empty or
non-present arguments.

=cut

sub take_action {
    my $self = shift;

    my $collection = Jifty::Collection->new(
        record_class => $self->record_class,
        current_user => $self->record->current_user
    );

    $collection->unlimit;

    for my $field (grep {$self->has_argument($_)} $self->argument_names) {
        my $value = $self->argument_value($field);
        if(defined($value)) {
            next if $value =~ /^\s*$/;
            $collection->limit(
                column => $field,
                value  => $value
               );
        } else {
            $collection->limit(
                column   => $field,
                value    => 'NULL',
                operator => 'IS'
               );
        }
    }

    $self->result->content(search => $collection);
    $self->result->success;
}

=head1 SEE ALSO

L<Jifty::Action::Record>, L<Jifty::Collection>

=cut

1;
