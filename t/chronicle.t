use strict;
use warnings;

use Test::More tests => 9;
use Test::NoWarnings;
use Data::Chronicle::Mock;
use Date::Utility;

my $d = { sample1 => [1, 2, 3],
          sample2 => [4, 5, 6],
          sample3 => [7, 8, 9] };

my $d_old = { sample1 => [2, 3, 5],
          sample2 => [6, 6, 14],
          sample3 => [9, 12, 13] };

my $first_save_epoch = time;

my ($chronicle_r, $chronicle_w) = Data::Chronicle::Mock::get_mocked_chronicle();

is $chronicle_w->set("log", "syslog", $d, Date::Utility->new(time)), 1, "data is stored without problem";
is_deeply $chronicle_r->get("log", "syslog"), $d, "data retrieval works";
is_deeply $chronicle_r->cache_reader->get("log::syslog"), JSON::to_json($d), "redis has stored correct data";

is $chronicle_w->set("log", "syslog-old", $d_old, Date::Utility->new(0)), 1, "data is stored without problem when specifying recorded date";

my $old_data = $chronicle_r->get_for("log", "syslog-old", 0);
is_deeply $old_data, $d_old, "data stored using recorded_date is retrieved successfully";

my $d2 = $chronicle_r->get("log", "syslog");
is_deeply $d, $d2, "data retrieval works";

my $d3 = { xsample1 => [10, 20, 30],
          xsample2 => [40, 50, 60],
          xsample3 => [70, 80, 90] };

is $chronicle_w->set("log", "syslog", $d3, Date::Utility->new(time + 2)), 1, "new version of the data is stored without problem";

my $d4 = $chronicle_r->get("log", "syslog");
is_deeply $d3, $d4, "data retrieval works for the new version";
