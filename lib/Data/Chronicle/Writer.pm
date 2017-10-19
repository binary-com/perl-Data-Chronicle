package Data::Chronicle::Writer;

use 5.014;
use strict;
use warnings;
use Data::Chronicle;
use Date::Utility;
use Encode qw(encode_utf8);
use JSON::MaybeXS;
use Moose;

=head1 NAME

Data::Chronicle::Writer - Provides writing to an efficient data storage for volatile and time-based data

=cut

## VERSION

=head1 DESCRIPTION

This module contains helper methods which can be used to store and retrieve information
on an efficient storage with below properties:

=over 4

=item B<Timeliness>

It is assumed that data to be stored are time-based meaning they change over time and the latest version is most important for us.

=item B<Efficient>

The module uses Redis cache to provide efficient data storage and retrieval.

=item B<Persistent>

In addition to caching every incoming data, it is also stored in PostgreSQL for future retrieval.

=item B<Transparent>

This modules hides all the details about distribution, caching, database structure and ... from developer. He only needs to call a method
to save data and another method to retrieve it. All the underlying complexities are handled by the module.

=back

=head1 Example

 my $d = get_some_log_data();

 my $chronicle_w = Data::Chronicle::Writer->new(
    cache_writer => $writer,
    dbic         => $dbic,
    ttl          => 86400);

 my $chronicle_r = Data::Chronicle::Reader->new(
    cache_reader => $reader,
    dbic         => $dbic);


 #store data into Chronicle - each time we call `set` it will also store
 #a copy of the data for historical data retrieval
 $chronicle_w->set("log_files", "syslog", $d);

 #retrieve latest data stored for syslog under log_files category
 my $dt = $chronicle_r->get("log_files", "syslog");

 #find historical data for `syslog` at given point in time
 my $some_old_data = $chronicle_r->get_for("log_files", "syslog", $epoch1);

=cut

has 'cache_writer' => (
    is      => 'ro',
    default => undef,
);

has 'dbic' => (
    isa     => 'Maybe[DBIx::Connector]',
    is      => 'ro',
    default => undef,
);

=head1 METHODS

=head2 ttl

If a TTL value is provided when constructing the instance, this will be used as the expiry time for the data.

Expiry time is not currently recorded in the PostgreSQL database backend - it is only used for the cache layer.

This represents the seconds until expiry, and default is C<undef>, meaning that keys will not expire.

=cut

has 'ttl' => (
    isa     => 'Maybe[Int]',
    is      => 'ro',
    default => undef,
);

=head2 publish_on_set

Will invoke

    $cache_writer->publish("$category::$name1", $value);

if set to true. This is useful, if to provide redis or postgres notificaitons on new data.

Default value: 0 (false)

=cut

has 'publish_on_set' => (
    isa     => 'Int',
    is      => 'ro',
    default => sub { 0 },
);

=head2 set

Example:

    $chronicle_writer->set("category1", "name1", $value1);

Store a piece of data "value1" under key "category1::name1" in Pg and Redis. Will
publish "category1::name1" in Redis if C<publish_on_set> is true.

=cut

sub set {
    my $self     = shift;
    my $category = shift;
    my $name     = shift;
    my $value    = shift;
    my $rec_date = shift;
    my $archive  = shift // 1;
    my $ttl      = shift // $self->ttl;

    die "Recorded date is undefined" unless $rec_date;
    die "Recorded date is not a Date::Utility object" if ref $rec_date ne 'Date::Utility';
    die "Cannot store undefined values in Chronicle!" unless defined $value;
    die "You can only store hash-ref or array-ref in Chronicle!" unless (ref $value eq 'ARRAY' or ref $value eq 'HASH');

    $value = JSON::MaybeXS->new->encode($value);

    my $key    = $category . '::' . $name;
    my $writer = $self->cache_writer;

    # publish & set in transaction
    $writer->multi;
    my $encoded = encode_utf8($value);
    $writer->publish($key, $encoded) if $self->publish_on_set;
    $writer->set(
        $key => $encoded,
        $ttl ? ('EX' => $ttl) : ());
    $writer->exec;

    $self->_archive($category, $name, $value, $rec_date) if $archive and $self->dbic;

    return 1;
}

sub _archive {
    my $self     = shift;
    my $category = shift;
    my $name     = shift;
    my $value    = shift;
    my $rec_date = shift;

    my $db_timestamp = $rec_date->db_timestamp;

    return $self->dbic->run(
        fixup => sub {
            $_->prepare(<<'SQL')->execute($category, $name, $value, $db_timestamp) });
WITH ups AS (
    UPDATE chronicle
       SET value=$3
     WHERE timestamp=$4
       AND category=$1
       AND name=$2
 RETURNING *
)
INSERT INTO chronicle (timestamp, category, name, value)
SELECT $4, $1, $2, $3
 WHERE NOT EXISTS (SELECT * FROM ups)
SQL
}

no Moose;

=head1 AUTHOR

Binary.com, C<< <support at binary.com> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-data-chronicle at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Data-Chronicle>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.




=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Data::Chronicle::Writer


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Data-Chronicle>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Data-Chronicle>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Data-Chronicle>

=item * Search CPAN

L<http://search.cpan.org/dist/Data-Chronicle/>

=back


=head1 ACKNOWLEDGEMENTS

=cut

1;
