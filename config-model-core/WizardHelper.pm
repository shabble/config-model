# $Author: ddumont $
# $Date: 2008-02-29 12:05:00 $
# $Name: not supported by cvs2svn $
# $Revision: 1.8 $

#    Copyright (c) 2006-2007 Dominique Dumont.
#
#    This file is part of Config-Model.
#
#    Config-Model is free software; you can redistribute it and/or
#    modify it under the terms of the GNU Lesser Public License as
#    published by the Free Software Foundation; either version 2.1 of
#    the License, or (at your option) any later version.
#
#    Config-Model is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#    Lesser Public License for more details.
#
#    You should have received a copy of the GNU Lesser Public License
#    along with Config-Model; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA

package Config::Model::WizardHelper ;
use Carp;
use strict;
use warnings ;
use Config::Model::ObjTreeScanner ;

use Config::Model::Exception ;
use Error qw(:try);

use vars qw($VERSION);
$VERSION = sprintf "%d.%03d", q$Revision: 1.8 $ =~ /(\d+)\.(\d+)/;

=head1 NAME

Config::Model::WizardHelper - Helps to create wizard widget for config models

=head1 SYNOPSIS

 use Config::Model ;

 my $inst   = $model -> instance ( root_class_name => 'Master', 
                                   instance_name => 'test1');

 my $root   = $inst -> config_root ;

 my $wizard = $inst -> wizard_helper ( leaf_cb => sub { ... },
                                       hash_element_cb => sub { ... } );
 $wizard->start ;

=head1 DESCRIPTION

This module provides a class that is able to scan a configuration tree and
will call back user defined subroutines on one of the following condition:

=over

=item *

A configuration item contains an error (mostly undefined mandatory
values)

=item *

A configuration item has a C<important> level. See 
L<level parameter|Config::Model::Node/"Configuration class declaration"> 
for details.

=back

By default, the wizard will only scan element with an C<intermediate>
permission.

The wizard helper supports going forward and backward during the scan
(to support C<back> and C<next> buttons on a wizard widget).

=head1 CONSTRUCTOR

The constructor should be used only by L<Config::Model::Instance> with
the L<wizard_helper|Config::Model::Instance/"wizard_helper ( ... )">
method.

=head1 Creating a wizard helper

A wizard helper will need at least two kind of call-back that must be
provided by the user: a call-back for leaf elements and a call-back
for hash elements (which will be also used for list elements).

These call-back must be passed when creating the wizard object (the
parameters are named C<leaf_cb> and C<hash_element_cb>)

Here are the the parameters accepted by C<wizard_helper>:

=head2 call_back_on_important

Whether to call back when an important element is found (default 1).

=head2 permission

Specifies the permission of the element scanned by the wizard (default
'intermediate').

=head2 leaf_cb

Subroutine called backed for leaf elements. See
L<Config::Model::ObjTreeScanner/"Callback prototypes"> for signature
and details. (mandatory)

=head2 hash_element_cb

Subroutine called backed for hash elements. See
L<Config::Model::ObjTreeScanner/"Callback prototypes"> for signature
and details. (mandatory)

=head1 Custom callbacks

By default, C<leaf_cb> will be called for all types of leaf elements
(i.e enum. integer, strings, ...). But you can provide dedicated
call-back for each type of leaf: 

 enum_value_cb, integer_value_cb, number_value_cb, boolean_value_cb,
 uniline_value_cb, string_value_cb

Likewise, you can also provide a call-back dedicated to list elements with
C<list_element_cb>

=cut


sub new {
    my $type = shift; 
    my %args = @_ ;

    my $self = {
		call_back_on_important => 1 ,
		forward                => 1 ,
	       } ;

    foreach my $p (qw/root/) {
	$self->{$p} = delete $args{$p} or
	  croak "WizardHelper->new: Missing $p parameter" ;
    }

    foreach my $p (qw/call_back_on_important/) {
	$self->{$p} = delete $args{$p} if defined $args{$p} ;
    }

    bless $self, $type ;

    my %user_scan_args = ( permission => 'intermediate',) ;

    foreach my $p (qw/permission/) {
	$user_scan_args{$p} = delete $args{$p};
    }

    my %cb_hash ;
    # mandatory call-back parameters 
    foreach my $item (qw/leaf_cb hash_element_cb/) {
	$cb_hash{$item} = delete $args{$item} or
	  croak "WizardHelper->new: Missing $item parameter" ;
    }

    # handle optional list_element_cb parameter
    $cb_hash{list_element_cb} = delete $args{list_element_cb} || $cb_hash{hash_element_cb} ;

    # optional call-back parameter
    $cb_hash{check_list_element_cb} 
      = delete $args{check_list_element_cb} || $cb_hash{leaf_cb};

    # optional call-back parameters 
    foreach my $p (qw/enum_value reference_value
                      integer_value number_value
                      boolean_value string_value uniline_value/
		  ) {
	my $item = $p.'_cb' ;
	$cb_hash{$item} = delete $args{$item} || $cb_hash{leaf_cb};
    }

    $self->{dispatch_cb}    = \%cb_hash ;
    $self->{user_scan_args} = \%user_scan_args ;

    # user call-back are *not* passed to ObjTreeScanner. They will be
    # called indirectly through wizard-helper own call-backs

    $self->{scanner} = Config::Model::ObjTreeScanner
      -> new ( fallback        => 'all' ,
	       permission      => $user_scan_args{permission} ,
	       hash_element_cb => sub { $self -> hash_element_cb (@_) },
	       node_content_cb => sub { $self -> node_content_cb (@_) },
	       leaf_cb         => sub { $self -> leaf_cb (@_) },
	     );

    return $self ;
}

=head1 Methods

=head2 start

Start the scan and perform call-back when needed. This function will return
when the scan is completely done.

=cut

sub start {
    my $self = shift ;
    $self->{scanner}->scan_node(undef, $self->{root}) ;
}

# internal. This call-back is passed to ObjTreeScanner. It will call
# scan_element in an order which depends on $self->{forward}.
sub node_content_cb {
    my ($self,$scanner, $data_r, $node,@element) = @_ ;

    warn "wiz_walk, node_content_cb called on '", $node->name,
      "' element: @element\n" if $::verbose;

    my $i = $self->{forward} == 1 ? 0 : $#element ;

    while ($i >= 0 and $i < @element) {
	my $element = $element[$i] ;
	warn "wiz_walk, node_content_cb calls scan_element ",
	  "on element $element\n"
	    if $::verbose;
	$self->{scanner}->scan_element($data_r,$node,$element) ;
	$i += $self->{forward} ;
    }
}

# internal. Used to find which user call-back to use for a given
# element type.
sub get_cb {
    my $self = shift;
    my $elt_type = shift ;
    return $self->{dispatch_cb}{$elt_type.'_cb'}
      || croak "wizard get_cb: unexpected type $elt_type" ;
}

# internal. This call-back is passed to ObjTreeScanner. It will call
# scan_hash in an order which depends on $self->{forward}.  it will
# also check if the hash (or list) element is flagged as 'important'
# and call user's hash or list call-back if needed
sub hash_element_cb {
    my ($self,$scanner, $data_r,$node,$element) = splice @_,0,5 ;
    my @keys = sort @_ ;

    warn "wiz_walk, hash_element_cb (element $element) called on '", $node->name,
      "' keys: '@keys' \n" if $::verbose;

    # get the call-back to use
    my $cb = $self->get_cb( $node -> element_type($element) . '_element') ;

    # use the same algorithm for check_important and
    # scan_element pseudo elements
    my $i = $self->{forward} == 1 ? 0 : 1 ;
    my $level 
      = $node->get_element_property(element => $element, property => 'level');

    while ($i >= 0 and $i < 2) {
	if ($self->{call_back_on_important} and $i == 0 and $level eq 'important') {
	    $cb->($self,$data_r,$node,$element,@keys) ;
	    # recompute keys as they may have been modified during call-back
	    @keys = $self->{scanner}->get_keys($node,$element) ;
	}

	if ($i == 1) {
	    my $j = $self->{forward} == 1 ? 0 : $#keys ;
	    while ($j >= 0 and $j < @keys) {
		my $k = $keys[$j] ;
		warn "wiz_walk, hash_element_cb (element $element) calls ",
		  "scan_hash on key $k\n" if $::verbose;
		$self->{scanner}->scan_hash($data_r,$node,$element,$k) ;
		$j += $self->{forward} ;
	    }
	}
	$i += $self->{forward} ;
    }
}

# internal. This call-back is passed to ObjTreeScanner. It will also
# check if the leaf element is flagged as 'important' or if the leaf
# element contains an error (mostly undefined mandatory values) and
# call user's call-back if needed

sub leaf_cb {
    my ($self,$scanner, $data_r,$node,$element,$index,$value_obj) = @_ ;

    warn "wiz_walk,leaf_cb called on '", $node->name,
      "' element '$element'", defined $index ? ", index $index":'', "\n" 
	if $::verbose;

    my $elt_type = $node -> element_type($element) ;
    my $key = $elt_type eq 'leaf' ? $value_obj -> value_type . '_value'
            :                       $elt_type.'_element' ;

    my $user_leaf_cb = $self->get_cb( $key) ;

    my $level 
      = $node->get_element_property(element => $element, property => 'level');

    if ($self->{call_back_on_important} and $level eq 'important') {
	warn "leaf_cb found important elt: '", $node->name,
	  "' element $element", defined $index ? ", index $index":'', "\n" 
	    if $::verbose;
	$user_leaf_cb->($self,$data_r,$node,$element,$index,$value_obj) ;
    }

    # now need to check for errors...
    my $result;
    try {
	$result = $value_obj->fetch();
    }
    catch Config::Model::Exception::User with {
	# ignore errors that has just been catched and call user call-back
	my $error_msg = shift ;
	warn "leaf_cb oopsed on '", $node->name,
	  "' element $element", defined $index ? ", index $index":'', "\n" 
	    if $::verbose;
	$user_leaf_cb->($self,$data_r,$node,$element,$index,$value_obj , $error_msg) ;
    }
    otherwise {
        my $oops = shift ;
	die $oops ;
        # does not return ...
    } ;

}

=head2 go_forward

Set wizard in forward (default) mode.

=cut

sub go_forward {
    my $self = shift ;
    warn "WizardHelper: going forward\n" 
      if $::verbose && $self ->{forward} == -1 ;
    $self ->{forward} = 1 ; 
}

=head2 go_backward

Set wizard in backward mode.

=cut

sub go_backward {
    my $self = shift ;
    warn "WizardHelper:: going backward\n" 
      if $::verbose && $self ->{forward} == 1 ;
    $self ->{forward} = -1 ; 
}


1;

=head1 AUTHOR

Dominique Dumont, (ddumont at cpan dot org)

=head1 SEE ALSO

L<Config::Model>,
L<Config::Model::Instance>,
L<Config::Model::Node>,
L<Config::Model::HashId>,
L<Config::Model::ListId>,
L<Config::Model::Value>,
L<Config::Model::CheckList>,
L<Config::Model::ObjTreeScanner>,

=cut
