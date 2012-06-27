#!/usr/bin/env perl
#############################################################################
##
## Copyright (C) 2012 Nokia Corporation and/or its subsidiary(-ies).
## Contact: http://www.qt-project.org/
##
## This file is part of the Quality Assurance module of the Qt Toolkit.
##
## $QT_BEGIN_LICENSE:LGPL$
## GNU Lesser General Public License Usage
## This file may be used under the terms of the GNU Lesser General Public
## License version 2.1 as published by the Free Software Foundation and
## appearing in the file LICENSE.LGPL included in the packaging of this
## file. Please review the following information to ensure the GNU Lesser
## General Public License version 2.1 requirements will be met:
## http://www.gnu.org/licenses/old-licenses/lgpl-2.1.html.
##
## In addition, as a special exception, Nokia gives you certain additional
## rights. These rights are described in the Nokia Qt LGPL Exception
## version 1.1, included in the file LGPL_EXCEPTION.txt in this package.
##
## GNU General Public License Usage
## Alternatively, this file may be used under the terms of the GNU General
## Public License version 3.0 as published by the Free Software Foundation
## and appearing in the file LICENSE.GPL included in the packaging of this
## file. Please review the following information to ensure the GNU General
## Public License version 3.0 requirements will be met:
## http://www.gnu.org/copyleft/gpl.html.
##
## Other Usage
## Alternatively, this file may be used in accordance with the terms and
## conditions contained in a signed written agreement between you and Nokia.
##
##
##
##
##
##
## $QT_END_LICENSE$
##
#############################################################################

use strict;
use warnings;

=head1 NAME

10-summarize-jenkins-build.t - simple test for summarize-jenkins-build.pl

=head1 SYNOPSIS

  perl 10-summarize-jenkins-build.t

This test invokes summarize-jenkins-build.pl with fake input and verifies
the output. Mocking is used to avoid fetching from any remote servers.

=cut

use File::Spec::Functions;
use FindBin;
use Readonly;
use Sub::Override;
use Test::More;

Readonly my $SCRIPT => catfile( $FindBin::Bin, '..', 'summarize-jenkins-build.pl' );
Readonly my $PACKAGE => 'QtQA::App::SummarizeJenkinsBuild';

# Do a single test run.
# Accepts the following arguments:
#
#   name => the human-readable name for this test
#   object => QtQA::App::SummarizeJenkinsBuild object
#   url => url to summarize
#   fake_json => ref to a hash containing (key,value) pairs, where keys are
#       URLs and values are the fake JSON text to return for a URL
#   expected_output => expected output of the summarize_jenkins_build function
#
sub do_test
{
    my (%args) = @_;

    my $o = $args{ object };
    my $name = $args{ name };

    my @mock_subs;
    if (my $fake_json = $args{ fake_json }) {
        push @mock_subs, Sub::Override->new(
            "${PACKAGE}::get_json_from_url",
            sub {
                my ($url) = @_;
                my $json = $fake_json->{ $url };
                ok( defined( $json ), "$name: $url fetched as expected" );
                return $json;
            },
        );
    }

    # Give parse_build_log.pl some predictable fake output
    push @mock_subs, Sub::Override->new(
        "${PACKAGE}::run_parse_build_log",
        sub {
            my ($url) = @_;
            print "(parse_build_log.pl output for $url)\n";
            return 0;
        },
    );

    my $output = $o->summarize_jenkins_build( $args{ url } );
    is( $output, $args{ expected_output }, "$name: summarize_jenkins_build output as expected" );

    return;
}

# Run all defined tests, on the given object $o
sub run_object_tests
{
    my ($o) = @_;

    my $url = 'some-url';

    do_test(
        name => 'simple success',
        object => $o,
        url => $url,
        fake_json => {
            $url => '{"number":1,"result":"SUCCESS","fullDisplayName":"quux"}',
        },
        expected_output => 'quux: SUCCESS',
    );

    $url = 'http://example.com/jenkins/123';
    do_test(
        name => 'simple failure',
        object => $o,
        url => $url,
        fake_json => {
            $url => '{"number":2,"result":"FAILURE","fullDisplayName":"bar build 2"}',
        },
        expected_output => 'bar build 2: FAILURE',
    );

    do_test(
        name => 'simple failure with master log',
        object => $o,
        url => $url,
        fake_json => {
            $url => '{"number":3,"result":"FAILURE","fullDisplayName":"bar build 3","url":"fake-url"}',
        },
        expected_output =>
            "(parse_build_log.pl output for fake-url/consoleText)\n"
           ."  Build log: fake-url/consoleText",
    );

    do_test(
        name => 'failure with master and configuration logs',
        object => $o,
        url => $url,
        fake_json => {
            $url => <<'END'
{
    "number":4,
    "result":"FAILURE",
    "fullDisplayName":"bar build 4",
    "url":"master-url",
    "runs":[
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":4,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":4,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
        },
        expected_output =>
            "(parse_build_log.pl output for cfg1-url/consoleText)\n"
           ."  Build log: cfg1-url/consoleText"
           ."\n\n--\n\n"
           ."(parse_build_log.pl output for cfg3-url/consoleText)\n"
           ."  Build log: cfg3-url/consoleText"
    );

    do_test(
        name => 'aborted ignores failure logs',
        object => $o,
        url => $url,
        fake_json => {
            $url => <<'END'
{
    "number":5,
    "result":"ABORTED",
    "fullDisplayName":"bar build 5",
    "url":"master-url",
    "runs":[
        {"number":5,"result":"FAILURE","fullDisplayName":"cfg1","url":"cfg1-url"},
        {"number":5,"result":"SUCCESS","fullDisplayName":"cfg2","url":"cfg2-url"},
        {"number":5,"result":"FAILURE","fullDisplayName":"cfg3","url":"cfg3-url"},
        {"number":6,"result":"FAILURE","fullDisplayName":"not-this","url":"not-this-url"}
    ]
}
END
        },
        expected_output => 'bar build 5: ABORTED',
    );

    return;
}

# main entry point
sub run
{
    ok( do $SCRIPT, "$PACKAGE loads OK" )
        || diag $@;

    my $object = $PACKAGE->new( );
    ok( $object, "$PACKAGE created OK" );
    run_object_tests( $object );

    done_testing( );

    return;
}

run() unless caller;
1;
