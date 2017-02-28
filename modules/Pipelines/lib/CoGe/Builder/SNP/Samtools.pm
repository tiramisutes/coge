package CoGe::Builder::SNP::Samtools;

use Moose;
extends 'CoGe::Builder::SNP::Analyzer';

use Carp;
use Data::Dumper;
use File::Spec::Functions qw(catdir catfile);
use File::Basename qw(basename);

use CoGe::Accessory::Web;
use CoGe::Accessory::Utils;
use CoGe::Core::Storage;
use CoGe::Core::Metadata;
use CoGe::Exception::Generic;

sub build {
    my $self = shift;
    my %opts = @_;
    my $fasta_file = $opts{fasta_file};
    my ($bam_file) = @{$opts{data_files}};

    unless ($fasta_file) {
        CoGe::Exception::Generic->throw(message => 'Missing fasta');
    }
    unless ($bam_file) {
        CoGe::Exception::Generic->throw(message => 'Missing bam');
    }

    my $gid = $self->request->genome->id;

    #
    # Build workflow
    #

    $self->add(
        $self->find_snps($fasta_file, $bam_file)
    );

    $self->add(
        $self->filter_snps($self->previous_output)
    );

    $self->vcf($self->previous_output);
    
    $self->add(
        $self->load_vcf(
            vcf         => $self->vcf,
            annotations => $self->generate_additional_metadata(), #TODO use metadata file instead
            gid         => $gid
        )
    );
}

sub find_snps {
    my $self = shift;
    my $fasta = shift;
    my $bam = shift;

    my $output_file = qq[$bam.raw.bcf];

    # Pipe commands together
    my $sam_command = get_command_path('SAMTOOLS');
    $sam_command .= " mpileup -u -f " . basename($fasta) . ' ' . basename($bam);
    my $bcf_command = get_command_path('BCFTOOLS');
    $bcf_command .= " view -b -v -c -g";

    # Get the output filename
    my $output = basename($output_file);

    return {
        cmd => qq[$sam_command | $bcf_command - > $output],
        inputs => [
            $fasta,
            $fasta . '.fai',
            $bam
        ],
        outputs => [ $output_file ],
        description => "Identifying SNPs using SAMtools method"
    };
}

sub filter_snps {
    my $self = shift;
    my $bcf_file = shift;

    my $output_file = qq[$bcf_file.vcf];

    my $params = $self->params->{snp_params};
    my $min_read_depth = $params->{'min-read-depth'} // 6;
    my $max_read_depth = $params->{'max-read-depth'} // 10;

    # Pipe commands together
    my $bcf_command = get_command_path('BCFTOOLS');
    $bcf_command .= " view " . basename($bcf_file);
    my $vcf_command = get_command_path('VCFTOOLS', 'vcfutils.pl');
    $vcf_command .= " varFilter -d $min_read_depth -D $max_read_depth";

    # Get the output filename
    my $output = basename($output_file);

    return {
        cmd => qq[$bcf_command | $vcf_command > $output],
        inputs  => [ $bcf_file ],
        outputs => [ $output_file ],
        description => "Filtering SNPs"
    };
}

sub generate_additional_metadata {
    my $self = shift;
    my $params = $self->params->{snp_params};
    
    my @annotations;
    push @annotations, qq{https://genomevolution.org/wiki/index.php?title=LoadExperiment||note|Generated by CoGe's NGS Analysis Pipeline};
    
    my $min_read_depth = $params->{'min-read-depth'} || 6;
    my $max_read_depth = $params->{'max-read-depth'} || 10;
    push @annotations, qq{note|SNPs generated using SAMtools method, min read depth $min_read_depth, max read depth $max_read_depth};
    
    return \@annotations;
}

1;
