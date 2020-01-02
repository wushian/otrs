# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::PostMaster::LoopProtection::DB;

use strict;
use warnings;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # get needed  objects
    for (qw(DBObject LogObject ConfigObject)) {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }

    # get config options
    $Self->{PostmasterMaxEmails} = $Self->{ConfigObject}->Get('PostmasterMaxEmails') || 40;

    # create logfile name
    my ( $Sec, $Min, $Hour, $Day, $Month, $Year ) = localtime(time);
    $Year = $Year + 1900;
    $Month++;
    $Self->{LoopProtectionDate} .= $Year . '-' . $Month . '-' . $Day;

    return $Self;
}

sub SendEmail {
    my ( $Self, %Param ) = @_;

    my $To = $Param{To} || return;

    # insert log
    return if !$Self->{DBObject}->Do(
        SQL => "INSERT INTO ticket_loop_protection (sent_to, sent_date)"
            . " VALUES ('"
            . $Self->{DBObject}->Quote($To)
            . "', '$Self->{LoopProtectionDate}')",
    );

    # delete old enrties
    return if !$Self->{DBObject}->Do(
        SQL => "DELETE FROM ticket_loop_protection WHERE "
            . " sent_date != '$Self->{LoopProtectionDate}'",
    );
    return 1;
}

sub Check {
    my ( $Self, %Param ) = @_;

    my $To    = $Param{To} || return;
    my $Count = 0;

    # check existing logfile
    my $SQL = "SELECT count(*) FROM ticket_loop_protection "
        . " WHERE sent_to = '" . $Self->{DBObject}->Quote($To) . "' AND "
        . " sent_date = '$Self->{LoopProtectionDate}'";
    $Self->{DBObject}->Prepare( SQL => $SQL );
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {
        $Count = $Row[0];
    }

    # check possible loop
    if ( $Count >= $Self->{PostmasterMaxEmails} ) {
        $Self->{LogObject}->Log(
            Priority => 'notice',
            Message =>
                "LoopProtection: send no more emails to '$To'! Max. count of $Self->{PostmasterMaxEmails} has been reached!",
        );
        return;
    }
    return 1;
}

1;
