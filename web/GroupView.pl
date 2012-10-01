#! /usr/bin/perl -w

use strict;
use CGI;
#use CGI::Ajax;
use JSON::XS;
use CoGe::Accessory::LogUser;
use CoGe::Accessory::Web;
use CoGeX;
use HTML::Template;
use Digest::MD5 qw(md5_base64);
use URI::Escape;
use Data::Dumper;
use File::Path;

no warnings 'redefine';

use vars qw($P $DBNAME $DBHOST $DBPORT $DBUSER $DBPASS $connstr $PAGE_NAME 
			$TEMPDIR $USER $DATE $BASEFILE $coge $cogeweb %FUNCTION 
			$COOKIE_NAME $FORM $URL $COGEDIR $TEMPDIR $TEMPURL);
$P = CoGe::Accessory::Web::get_defaults( $ENV{HOME} . 'coge.conf' );

$DATE = sprintf(
	"%04d-%02d-%02d %02d:%02d:%02d",
	sub { ( $_[5] + 1900, $_[4] + 1, $_[3] ), $_[2], $_[1], $_[0] }->(localtime)
);
$PAGE_NAME = 'GroupView.pl';

$FORM = new CGI;

$DBNAME  = $P->{DBNAME};
$DBHOST  = $P->{DBHOST};
$DBPORT  = $P->{DBPORT};
$DBUSER  = $P->{DBUSER};
$DBPASS  = $P->{DBPASS};
$connstr = "dbi:mysql:dbname=" . $DBNAME . ";host=" . $DBHOST . ";port=" . $DBPORT;
$coge = CoGeX->connect( $connstr, $DBUSER, $DBPASS );

$COOKIE_NAME = $P->{COOKIE_NAME};
$URL         = $P->{URL};
$COGEDIR     = $P->{COGEDIR};
$TEMPDIR     = $P->{TEMPDIR} . "GroupView/";
mkpath( $TEMPDIR, 0, 0777 ) unless -d $TEMPDIR;
$TEMPURL = $P->{TEMPURL} . "GroupView/";

my ($cas_ticket) = $FORM->param('ticket');
$USER = undef;
($USER) = CoGe::Accessory::Web->login_cas( cookie_name => $COOKIE_NAME, ticket => $cas_ticket, coge => $coge, this_url => $FORM->url() ) if ($cas_ticket);
($USER) = CoGe::Accessory::LogUser->get_user( cookie_name => $COOKIE_NAME, coge => $coge ) unless $USER;

my $link = "http://" . $ENV{SERVER_NAME} . $ENV{REQUEST_URI};
$link = CoGe::Accessory::Web::get_tiny_link( db => $coge, user_id => $USER->id, page => $PAGE_NAME, url => $link );

%FUNCTION = (
	gen_html                 => \&gen_html,
	get_group_info           => \&get_group_info,
	edit_group_info          => \&edit_group_info,
	update_group_info        => \&update_group_info,
	modify_users             => \&modify_users,
	add_user_to_group        => \&add_user_to_group,
	remove_user_from_group   => \&remove_user_from_group,
	add_lists                => \&add_lists,
	add_list_to_group        => \&add_list_to_group,
	remove_list_from_group   => \&remove_list_from_group,	
	search_lists             => \&search_lists,
	get_list_preview         => \&get_list_preview,
	delete_group             => \&delete_group,
	dialog_set_group_creator => \&dialog_set_group_creator,
	set_group_creator      	 => \&set_group_creator,
);

dispatch();

sub dispatch {
	my %args  = $FORM->Vars;
	my $fname = $args{'fname'};
	if ($fname) {
		die "Uknown AJAX function '$fname'" if not defined $FUNCTION{$fname};
		#print STDERR Dumper \%args;
		if ( $args{args} ) {
			my @args_list = split( /,/, $args{args} );
			print $FORM->header, $FUNCTION{$fname}->(@args_list);
		}
		else {
			print $FORM->header, $FUNCTION{$fname}->(%args);
		}
	}
	else {
		print $FORM->header, gen_html();
	}
}

sub gen_html {
	my $html;
	my $template = HTML::Template->new( filename => $P->{TMPLDIR} . 'generic_page.tmpl' );
	$template->param( HELP => '/wiki/index.php?title=GroupView' );
	my $name = $USER->user_name;
	$name = $USER->first_name if $USER->first_name;
	$name .= " " . $USER->last_name if $USER->first_name && $USER->last_name;
	$template->param( USER       => $name );
	$template->param( TITLE      => qq{} );
	$template->param( PAGE_TITLE => qq{GroupView} );
	$template->param( LOGO_PNG   => "GroupView-logo.png" );
	$template->param( LOGON      => 1 ) unless $USER->user_name eq "public";
	$template->param( DATE       => $DATE );
	$template->param( BODY       => gen_body() );
	$template->param( ADJUST_BOX => 1 );
	$html .= $template->output;
}

sub gen_body {
	my $template = HTML::Template->new( filename => $P->{TMPLDIR} . 'GroupView.tmpl' );
	$template->param( PAGE_NAME  => $FORM->url );
	$template->param( MAIN       => 1 );
	my $ugid = $FORM->param('ugid');
	my ($group_info) = get_group_info( ugid => $ugid );
	$template->param( GROUP_INFO => $group_info );
	$template->param( UGID       => $ugid );
	
	$template->param( ADMIN_AREA => $USER->is_admin );
	$template->param( ADMIN_BUTTONS => get_admin_functions() );

#	my $open;
#	$open = $FORM->param('open') if defined $FORM->param('open');
#	my $box_open = $open ? 'true' : 'false';
#	$template->param( EDIT_BOX_OPEN => $box_open );
	
	return $template->output;
}

sub get_admin_functions {
	my $ugid = $FORM->param('ugid');
	my $html = qq{<span style="font-size: .75em" class='ui-button ui-button-go ui-corner-all' onClick="dialog_set_group_creator({ugid: '$ugid'});">Set Group Creator</span>};
	return $html;
}

sub get_roles {
	my $current_role_id = shift;
	
	my @roles;
	foreach my $role ( $coge->resultset('Role')->all() ) {
		next if ($role->name =~ /admin/i && !$USER->is_admin);
		next if ($role->name =~ /owner/i && !$USER->is_admin);
		my $name = $role->name . ($role->description ? ' (' . $role->description . ')' : '');
		my $selected = '';
		$selected = 'selected="selected"' if ($role->id == $current_role_id);
		push @roles, { ROLE_ID => $role->id, ROLE_NAME => $name, ROLE_SELECTED => $selected };
	}
	return \@roles;
}

sub get_group_info {
	my %opts = @_;
	my $ugid = $opts{ugid};
	return "Must have valid user group id.\n" unless ($ugid);
	
	my ($group) = $coge->resultset('UserGroup')->find($ugid);
	return "User group id$ugid does not exist.<br>" .
			"Click <a href='Groups.pl'>here</a> to view all groups." unless ($group);

	my $user_can_edit = (user_can_edit($group) and (not $group->locked or $USER->is_admin));
	
	my $html = $group->annotation_pretty_print_html(allow_delete => $user_can_edit);
	if ($user_can_edit) {
		$html .= qq{<span style="font-size: .75em" class='ui-button ui-button-go ui-corner-all' onClick="edit_group_info({ugid: '$ugid'});">Edit Group Info</span>};
		$html .= qq{<span style="font-size: .75em" class='ui-button ui-button-go ui-corner-all' onClick="modify_users({ugid: '$ugid'});">Modify Users</span>};
		$html .= qq{<span style="font-size: .75em" class='ui-button ui-button-go ui-corner-all' onClick="add_lists({ugid: '$ugid'});">Add Lists</span>};
		$html .= qq{<span style="font-size: .75em" class='ui-button ui-button-go ui-corner-all' onClick="dialog_delete_group();">Delete Group</span>};
	}
	
	return $html;
}

sub edit_group_info {
	my %opts = @_;
	my $ugid  = $opts{ugid};
	return 0 unless $ugid;

	my $group = $coge->resultset('UserGroup')->find($ugid);
	return 0 unless user_can_edit($group);
	
	my $template = HTML::Template->new( filename => $P->{TMPLDIR} . 'GroupView.tmpl' );
	$template->param( EDIT_GROUP_INFO => 1 );
	$template->param( UGID            => $ugid );
	$template->param( NAME            => $group->name );
	$template->param( DESC            => $group->description );
	$template->param( ROLE_LOOP       => get_roles($group->role->id) );

	my %data;
	$data{title} = 'Edit Group Info';
	$data{name}   = $group->name;
	$data{desc}   = $group->description;
	$data{output} = $template->output;

	return encode_json( \%data );
}

sub update_group_info {
	my %opts = @_;
	my $ugid  = $opts{ugid};
	return 0 unless $ugid;
	my $name = $opts{name};
	return 0 unless $name;

	my $desc = $opts{desc};
	my $group = $coge->resultset('UserGroup')->find($ugid);
	return 0 unless user_can_edit($group);
	
	$group->name($name);
	$group->description($desc) if $desc;
	$group->update;

	return 1;
}

sub modify_users {
	my %opts = @_;
	my $ugid = $opts{ugid};
	return 0 unless $ugid;
	
	my $group = $coge->resultset('UserGroup')->find($ugid);
	return 0 unless user_can_edit($group);
	
	my %data;
	$data{title} = 'Modify Users';
	my %users;
	my @users;

	foreach my $user (sort { $a->last_name cmp $b->last_name || $a->user_name cmp $b->user_name } $group->users)
	{
#		next if $user->user_name eq $USER->user_name; #skip self;
		push @users, { uid_name => $user->info, uid => $user->id };
		$users{ $user->id } = 1;
	}
	$data{users} = \@users;
	
	my @all_users;
	foreach my $user ( sort { $a->last_name cmp $b->last_name || $a->user_name cmp $b->user_name } $coge->resultset('User')->all )
	{
		next if $users{ $user->id };    #skip users we already have
		push @all_users, { uid_name => $user->info, uid => $user->id };
	}
	$data{all_users} = \@all_users;

	my $template = HTML::Template->new( filename => $P->{TMPLDIR} . 'GroupView.tmpl' );
	$template->param( MODIFY_USERS => 1 );
	$template->param( UGID         => $ugid );
	$template->param( UGID_LOOP     => $data{users} );
	$template->param( ALL_UGID_LOOP => $data{all_users} );

	$data{output} = $template->output;
	return encode_json( \%data );
}

sub add_user_to_group {
	my %opts = @_;
	my $ugid = $opts{ugid};
	my $uid  = $opts{uid};

	#return 1 if $uid == $USER->id;
	return "UGID and/or UID not specified" unless $ugid && $uid;
	my $group = $coge->resultset('UserGroup')->find($ugid);
	return 0 unless user_can_edit($group);
	
	if ( $group->locked && !$USER->is_admin ) {
		return "This is a locked group.  Admin permission is needed to modify.";
	}
	
	my @res = $coge->resultset('UserGroupConnector')->search( { user_id => $uid, user_group_id => $ugid } );
	return 1 if @res; # previously added;
	
	my ($ugc) = $coge->resultset('UserGroupConnector')->create( { user_id => $uid, user_group_id => $ugid } );
	
	return 1;
}

sub remove_user_from_group {
	my %opts = @_;
	my $ugid = $opts{ugid};
	my $uid  = $opts{uid};
	
	if ( $uid == $USER->id && !$USER->is_admin ) { # only allow this for admins
		return "Can't remove yourself from this group!";
	}
	
	my $group = $coge->resultset('UserGroup')->find($ugid);
	return 0 unless user_can_edit($group);
	
	if ( $group->locked && !$USER->is_admin ) {
		return "This is a locked group.  Admin permission is needed to modify.";
	}

	foreach my $ugc ( $coge->resultset('UserGroupConnector')->search( { user_id => $uid, user_group_id => $ugid } ) ) {
		$ugc->delete;
	}
	
	return 1;
}

sub add_lists {
	my %opts = @_;
	my $ugid  = $opts{ugid};
	return 0 unless $ugid;

	my $group = $coge->resultset('UserGroup')->find($ugid);
	return 0 unless user_can_edit($group);
	
	my $template = HTML::Template->new( filename => $P->{TMPLDIR} . 'GroupView.tmpl' );
	$template->param( ADD_LISTS => 1 );
	$template->param( UGID      => $ugid );

	my %data;
	$data{title} = 'Add Lists';
	$data{output} = $template->output;

	return encode_json( \%data );
}

sub add_list_to_group {
	my %opts = @_;
	my $ugid  = $opts{ugid};
	return 0 unless $ugid;
	my $item_spec = $opts{item_spec};
	return 0 unless $item_spec;
#	print STDERR "$lid $item_spec\n";	
	
	# FIXME: check for user group locked?
	
	my ($item_type, $item_id) = split(/:/, $item_spec);
	my $list = $coge->resultset('List')->find($item_id);
	return 0 unless ($list);
	
	$list->user_group_id($ugid);
	$list->update;
	
	return 1;
}

sub remove_list_from_group {
	my %opts  = @_;
	my $ugid = $opts{ugid};
	return "No UGID specified" unless $ugid;
	my $lid = $opts{lid};
	return "No LID specified" unless $lid;
#	print STDERR "ugid=$ugid lid=$lid\n";
	
	my $group = $coge->resultset('UserGroup')->find($ugid);
	return 0 if ($group->locked and !$USER->is_admin);
	
	# FIXME: upon review, is this really what we want? what about reassignin the list to owner list instead?
	my $list = $coge->resultset('List')->find($lid);
	$list->delete();
	
	return 1;
}

sub search_lists { 
	my %opts = @_;
	my $ugid = $opts{ugid};
	my $search_term = $opts{search_term};
#	print STDERR "$ugid $search_term\n";
	return 0 unless $ugid;
	return '' unless $search_term;
	
	$search_term = '%'.$search_term.'%';
	
	my $group = $coge->resultset('UserGroup')->find($ugid);
	my %exists;
	map { $exists{$_->id}++ } $group->lists;
	
	my $group_str = join(',', map { $_->id } $USER->groups);
	
	my @lists;
	
	if ($USER->is_admin) {
		@lists = $coge->resultset("List")->search(
			\[ 'name LIKE ? OR description LIKE ?', 
			['name', $search_term ], ['description', $search_term] ]);		
	}
	else {
		@lists = $coge->resultset("List")->search_literal("locked=0 AND (restricted=0 OR user_group_id IN ( $group_str )) AND (name LIKE '$search_term' OR description LIKE '$search_term')");
	}
	
	my $html = '';
	foreach my $l (sort listcmp @lists) {
		my $disable = $exists{$l->id} ? "disabled='disabled'" : '';
		#next if ($l->id == $lid); # can't add a list to itself!
		my $item_spec = 1 . ':' . $l->id; #FIXME magic number for item_type
		$html .= "<option $disable value='$item_spec'>" . $l->info . "</option><br>\n";	
	}
	
	return $html;
}

# FIXME mdb 8/29/12 - this routine is redundantly declared (e.g. ListView.pl)
sub listcmp {
	no warnings 'uninitialized'; # disable warnings for undef values in sort
	$a->name cmp $b->name
}

sub get_list_preview {
	my %opts  = @_;
	my $item_spec = $opts{item_spec};

	my (undef, $lid) = split(':', $item_spec);

	my $list = $coge->resultset('List')->find($lid);
	my $html = '';
	if ($list) {
		my $contents_summary = $list->contents_summary_html;
		$html .= "List <b>'" . $list->name . "'</b> (id" . $list->id . ') ';
		if ($contents_summary) {
			$html .= 'contains:<div style="padding-left: 10px; padding-top: 3px;">' . $contents_summary . '</div>';
		}
		else {
			$html .= 'is empty.';
		}	
	}

	return $html;	
}

sub delete_group {
	my %opts  = @_;
	my $ugid = $opts{ugid};
	return "No UGID specified" unless $ugid;
	
	my $group = $coge->resultset('UserGroup')->find($ugid);
	
	return 0 unless user_can_edit();
	
	if ( $group->locked && !$USER->is_admin ) {
		return "This is a locked group.  Admin permission is needed to modify.";
	}
	
	# Reassign this group's lists to user's owner group
	my $owner_group = $USER->owner_group;
	foreach my $list ($group->lists) {
		$list->user_group_id( $owner_group->id );
		$list->update;
	}
	
	# OK, now delete the group
	$group->delete();
	
	$coge->resultset('Log')->create( { user_id => $USER->id, page => $PAGE_NAME, description => 'delete user group id' . $group->id } );
	
	return 1;
}

sub dialog_set_group_creator {
	my %opts = @_;
	my $ugid = $opts{ugid};
	return 0 unless $ugid;
	return 0 unless $USER->is_admin;
	
	my $group = $coge->resultset('UserGroup')->find($ugid);
	
	my %data;
	$data{title} = 'Set Creator';
	my %users;
	my @users;

	my @all_users;
	foreach my $user ( sort { $a->last_name cmp $b->last_name || $a->user_name cmp $b->user_name } $coge->resultset('User')->all )
	{
		next if $users{ $user->id };    #skip users we already have
		my $name = $user->user_name;
		$name .= " : " . $user->first_name if $user->first_name;
		$name .= " " . $user->last_name if $user->first_name && $user->last_name;
		push @all_users, { uid_name => $name, uid => $user->id };
	}
	$data{all_users} = \@all_users;

	my $template = HTML::Template->new( filename => $P->{TMPLDIR} . 'GroupView.tmpl' );
	$template->param( SET_GROUP_CREATOR => 1 );
	$template->param( UGID         => $ugid );
	$template->param( ALL_UGID_LOOP => $data{all_users} );

	$data{output} = $template->output;
	return encode_json( \%data );
}

sub set_group_creator {
	my %opts = @_;
	my $ugid = $opts{ugid};
	my $uid  = $opts{uid};
	return "UGID and/or UID not specified" unless $ugid && $uid;
	
	my $group = $coge->resultset('UserGroup')->find($ugid);
	return 0 unless user_can_edit($group);
	
	if ( $group->locked && !$USER->is_admin ) {
		return "This is a locked group.  Admin permission is needed to modify.";
	}

	$group->creator_user_id($uid);
	$group->update();	
	
	return 1;
}

sub user_can_edit {
	my $group = shift;
	return ($USER->is_admin or 
			$USER->is_owner_editor(group => $group) or 
			$USER->id == $group->creator->id);
}
