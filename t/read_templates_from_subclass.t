use strict;
use warnings;

use Template::Mustache;
use Test::More;

    {
        ## no critic (RequireFilenameMatchesPackage)
        package t::ReadTemplatesFromSubclass::Mustache;
        use base 'Template::Mustache';

        sub template {
            my $is_instance = ref(shift) ? 'yes' : 'no';
            return "{{name}} the {{occupation}} ($is_instance)";
        }

        sub name        { 'Joe' }
        sub occupation  { 'Plumber' }
    }

    subtest class_render => sub {
        my $rendered = t::ReadTemplatesFromSubclass::Mustache->render();
        is($rendered, "Joe the Plumber (no)");
    };

    subtest instance_render => sub {
        my $rendered = t::ReadTemplatesFromSubclass::Mustache->new()->render();
        is($rendered, "Joe the Plumber (yes)");
    };

done_testing;
