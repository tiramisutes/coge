package CoGe::Builder::Tools::SynMap3D;

use Moose;

use CoGe::Accessory::Jex;
use CoGe::Accessory::Web qw( get_defaults );
use CoGe::Accessory::Workflow;
use CoGe::Accessory::Utils qw(units);
use CoGe::Builder::CommonTasks qw( create_gff_generation_job );
use CoGe::Builder::Tools::SynMap qw( add_jobs defaults );
use CoGe::Core::Storage qw( get_workflow_paths );
use Data::Dumper;
#use File::Path qw(mkpath);
use File::Spec::Functions;
use JSON qw( encode_json );
use POSIX;

sub build {
	my $self = shift;
	my $xid = $self->params->{genome_id1};
	my $yid = $self->params->{genome_id2};
	my $zid = $self->params->{genome_id3};
	my ($dir1, $dir2) = sort($xid, $yid);
	my ($dir3, $dir4) = sort($xid, $zid);
	my ($dir5, $dir6) = sort($yid, $zid);

	# Add SynMap Jobs
	my @genome_ids;
	my $i = 1;
	while (1) {
		if ($self->params->{'genome_id' . $i}) {
			push @genome_ids, $self->params->{'genome_id' . $i++};
		}
		else {
			last;
		}
	}
	for (my $j=1; $j<$i-1; $j++) {
		for (my $k=$j+1; $k<$i; $k++) {
			$self->params->{genome_id1} = $genome_ids[$j-1];
			$self->params->{genome_id2} = $genome_ids[$k-1];
			my %opts = ( %{ defaults() }, %{ $self->params } );
			my $resp = add_jobs(
				workflow => $self->workflow,
				db       => $self->db,
				config   => $self->conf,
				user     => $self->user,
				%opts
			);
			if ($resp) { # an error occurred
			   return 0;
			}
		}
	}

	#########################################################################
	# Add merging job.
	#########################################################################
	my $workflow = $self->workflow;

	my $merger = 'synmerge_3.py';

	my $dot_xy_path = catfile($self->conf->{DIAGSDIR}, $dir1, $dir2, $dir1 . '_' . $dir2 . "_synteny.json");
    my $dot_xz_path = catfile($self->conf->{DIAGSDIR}, $dir3, $dir4, $dir3 . '_' . $dir4 . "_synteny.json");
	my $dot_yz_path = catfile($self->conf->{DIAGSDIR}, $dir5, $dir6, $dir5 . '_' . $dir6 . "_synteny.json");

	my $sort = $self->params->{sort};
    my $min_length = $self->params->{min_length};
    my $min_synteny = $self->params->{min_synteny};
    my $cluster = $self->params->{cluster};
    my $c_eps;
    my $c_min;
    if ($cluster eq 'true') {
        $c_eps = $self->params->{c_eps};
        $c_min = $self->params->{c_min};
    }
    my $ratio = $self->params->{ratio};
    my $r_by;
    my $r_min;
    my $r_max;
    if ($ratio ne 'false') {
        $r_by = $self->params->{r_by};
        $r_min = $self->params->{r_min};
        $r_max = $self->params->{r_max};
    }
    my $graph_out = $self->params->{graph_out};
    my $log_out = $self->params->{log_out};

	#my %config = $self->conf;
    my $SYN3DIR = $self->conf->{SYN3DIR};
    my $SCRIPTDIR = $self->conf->{SCRIPTDIR};


	my $merge_ids = ' -xid ' . $xid . ' -yid ' . $yid . ' -zid ' . $zid;
    my $merge_ins = ' -i1 ' . $dot_xy_path . ' -i2 ' . $dot_xz_path . ' -i3 ' . $dot_yz_path;
    my $merge_otp = ' -o ' . $SYN3DIR;
    my $merge_opt = ' -S ' . $sort . ' -ml ' . $min_length . ' -ms ' . $min_synteny;
    if ($cluster eq 'true') {
        $merge_opt .= ' -C -C_eps ' . $c_eps . ' -C_ms ' . $c_min;
    }
    if ($ratio ne 'false') {
        $merge_opt .= ' -R ' . $ratio . ' -Rby ' . $r_by . ' -Rmin ' . $r_min . ' -Rmax ' . $r_max;
    }
    my $merge_cmd = catfile($SCRIPTDIR, $merger) . $merge_ids . $merge_ins . $merge_opt . $merge_otp;
	# build merge inputs.
    my $merge_i = [$dot_xy_path, $dot_xz_path, $dot_yz_path];
    # buildmerge outputs.
    my $dot_xyz_path = catfile($SYN3DIR, $graph_out);
    my $log_xyz_path = catfile($SYN3DIR, $log_out);
    my $merge_o = [$dot_xyz_path, $log_xyz_path];

	$workflow->add_job({
        cmd => $merge_cmd,
        inputs => $merge_i,
        outputs => $merge_o,
        description => "Identifying common points & building graph object..."
    });

	return 1;
}

sub get_name {
	return 'SynMap3D';
}

with qw(CoGe::Builder::Buildable);

1;
