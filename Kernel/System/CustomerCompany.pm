# --
# Copyright (C) 2001-2020 OTRS AG, https://otrs.com/
# --
# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::System::CustomerCompany;

use strict;
use warnings;

use Kernel::System::Valid;

use vars qw(@ISA $VERSION);

=head1 NAME

Kernel::System::CustomerCompany - customer company lib

=head1 SYNOPSIS

All Customer Company functions. E.g. to add and update customer companies.

=head1 PUBLIC INTERFACE

=over 4

=cut

=item new()

create an object

    use Kernel::Config;
    use Kernel::System::Encode;
    use Kernel::System::Log;
    use Kernel::System::Main;
    use Kernel::System::Time;
    use Kernel::System::DB;
    use Kernel::System::CustomerCompany;

    my $ConfigObject = Kernel::Config->new();
    my $EncodeObject = Kernel::System::Encode->new(
        ConfigObject => $ConfigObject,
    );
    my $LogObject = Kernel::System::Log->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
    );
    my $TimeObject = Kernel::System::Time->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
    );
    my $MainObject = Kernel::System::Main->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
    );
    my $DBObject = Kernel::System::DB->new(
        ConfigObject => $ConfigObject,
        EncodeObject => $EncodeObject,
        LogObject    => $LogObject,
        MainObject   => $MainObject,
    );
    my $CustomerCompanyObject = Kernel::System::CustomerCompany->new(
        ConfigObject => $ConfigObject,
        LogObject    => $LogObject,
        DBObject     => $DBObject,
        TimeObject   => $TimeObject,
        EncodeObject => $EncodeObject,
        MainObject   => $MainObject,
    );

=cut

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {};
    bless( $Self, $Type );

    # check needed objects
    for (qw(DBObject ConfigObject LogObject MainObject EncodeObject)) {
        $Self->{$_} = $Param{$_} || die "Got no $_!";
    }

    $Self->{ValidObject} = Kernel::System::Valid->new( %{$Self} );

    # config options
    $Self->{CustomerCompanyTable} = $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{Table}
        || die "Need CustomerCompany->Params->Table in Kernel/Config.pm!";
    $Self->{CustomerCompanyKey} = $Self->{ConfigObject}->Get('CustomerCompany')->{CustomerCompanyKey}
        || $Self->{ConfigObject}->Get('CustomerCompany')->{Key}
        || die "Need CustomerCompany->CustomerCompanyKey in Kernel/Config.pm!";
    $Self->{CustomerCompanyMap} = $Self->{ConfigObject}->Get('CustomerCompany')->{Map}
        || die "Need CustomerCompany->Map in Kernel/Config.pm!";
    $Self->{CustomerCompanyValid} = $Self->{ConfigObject}->Get('CustomerCompany')->{'CustomerCompanyValid'};
    $Self->{SearchListLimit}      = $Self->{ConfigObject}->Get('CustomerCompany')->{'CustomerCompanySearchListLimit'};
    $Self->{SearchPrefix}         = $Self->{ConfigObject}->Get('CustomerCompany')->{'CustomerCompanySearchPrefix'};

    if ( !defined( $Self->{SearchPrefix} ) ) {
        $Self->{SearchPrefix} = '';
    }
    $Self->{SearchSuffix} = $Self->{ConfigObject}->Get('CustomerCompany')->{'CustomerCompanySearchSuffix'};
    if ( !defined( $Self->{SearchSuffix} ) ) {
        $Self->{SearchSuffix} = '*';
    }

    # charset settings
    my $DatabasePreferences = $Self->{ConfigObject}->Get('CustomerCompany')->{Params} || {};
    $Self->{SourceCharset} = $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{SourceCharset} || '';
    $Self->{DestCharset}   = $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{DestCharset}
        || '';
    $Self->{CharsetConvertForce} = $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{CharsetConvertForce} || '';
    if ( $Self->{SourceCharset} !~ /utf(-8|8)/i ) {
        $DatabasePreferences->{Encode} = 0;
    }

    # create new db connect if DSN is given
    if ( $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{DSN} ) {
        $Self->{DBObject} = Kernel::System::DB->new(
            LogObject    => $Param{LogObject},
            ConfigObject => $Param{ConfigObject},
            MainObject   => $Param{MainObject},
            EncodeObject => $Param{EncodeObject},
            DatabaseDSN  => $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{DSN},
            DatabaseUser => $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{User},
            DatabasePw   => $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{Password},
            Type         => $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{Type} || '',
            %{$DatabasePreferences},
        ) || die('Can\'t connect to database!');

        # remember that we don't have inherited the DBObject from parent call
        $Self->{NotParentDBObject} = 1;
    }

    # this setting specifies if the table has the create_time,
    # create_by, change_time and change_by fields of OTRS
    $Self->{ForeignDB} = $Self->{ConfigObject}->Get('CustomerCompany')->{Params}->{ForeignDB} ? 1 : 0;

    # set lower if database is case sensitive
    $Self->{Lower} = '';
    if ( !$Self->{DBObject}->GetDatabaseFunction('CaseInsensitive') ) {
        $Self->{Lower} = 'LOWER';
    }

    return $Self;
}

=item CustomerCompanyAdd()

add a new customer company

    my $ID = $CustomerCompanyObject->CustomerCompanyAdd(
        CustomerID              => 'example.com',
        CustomerCompanyName     => 'New Customer Company Inc.',
        CustomerCompanyStreet   => '5201 Blue Lagoon Drive',
        CustomerCompanyZIP      => '33126',
        CustomerCompanyCity     => 'Miami',
        CustomerCompanyCountry  => 'USA',
        CustomerCompanyComment  => 'some comment',
        ValidID                 => 1,
        UserID                  => 123,
    );

NOTE: Actual fields accepted by this API call may differ based on
CustomerCompany mapping in your system configuration.

=cut

sub CustomerCompanyAdd {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for (qw(CustomerID UserID)) {
        if ( !$Param{$_} ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $_!"
            );
            return;
        }
    }

    # build insert
    my $SQL = "INSERT INTO $Self->{CustomerCompanyTable} (";

    my $FieldInserted;
    for my $Entry ( @{ $Self->{CustomerCompanyMap} } ) {
        $SQL .= ', ' if ($FieldInserted);
        $SQL .= " $Entry->[2] ";
        $FieldInserted = 1;
    }

    if ( !$Self->{ForeignDB} ) {
        $SQL .= ', ' if ($FieldInserted);
        $SQL .= 'create_time, create_by, change_time, change_by';
    }
    $SQL .= ") VALUES (";

    my $ValueInserted;
    for my $Entry ( @{ $Self->{CustomerCompanyMap} } ) {

        $SQL .= ', ' if ($ValueInserted);

        if ( $Entry->[5] =~ /^int$/i ) {
            $SQL .= " " . $Self->{DBObject}->Quote( $Param{ $Entry->[0] }, 'Integer' );
        }
        else {
            $SQL .= " '" . $Self->{DBObject}->Quote( $Param{ $Entry->[0] } ) . "'";
        }

        $ValueInserted = 1;
    }

    if ( !$Self->{ForeignDB} ) {
        $SQL .= ', ' if ($ValueInserted);
        $SQL .= "current_timestamp, $Param{UserID}, current_timestamp, $Param{UserID}";
    }
    $SQL .= ")";

    $SQL = $Self->_ConvertTo($SQL);
    return if !$Self->{DBObject}->Do( SQL => $SQL );

    # log notice
    $Self->{LogObject}->Log(
        Priority => 'notice',
        Message =>
            "CustomerCompany: '$Param{CustomerCompanyName}/$Param{CustomerID}' created successfully ($Param{UserID})!",
    );

    return $Param{CustomerID};
}

=item CustomerCompanyGet()

get customer company attributes

    my %CustomerCompany = $CustomerCompanyObject->CustomerCompanyGet(
        CustomerID => 123,
    );

Returns:

    %CustomerCompany = (
        'CustomerCompanyName'    => 'Customer Company Inc.',
        'CustomerID'             => 'example.com',
        'CustomerCompanyStreet'  => '5201 Blue Lagoon Drive',
        'CustomerCompanyZIP'     => '33126',
        'CustomerCompanyCity'    => 'Miami',
        'CustomerCompanyCountry' => 'United States',
        'CustomerCompanyURL'     => 'http://example.com',
        'CustomerCompanyComment' => 'Some Comments',
        'ValidID'                => '1',
        'CreateTime'             => '2010-10-04 16:35:49',
        'ChangeTime'             => '2010-10-04 16:36:12',
    );

NOTE: Actual fields returned by this API call may differ based on
CustomerCompany mapping in your system configuration.

=cut

sub CustomerCompanyGet {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    if ( !$Param{CustomerID} ) {
        $Self->{LogObject}->Log(
            Priority => 'error',
            Message  => "Need CustomerID!"
        );
        return;
    }

    # build select
    my $SQL = "SELECT ";
    for my $Entry ( @{ $Self->{CustomerCompanyMap} } ) {
        $SQL .= " $Entry->[2], ";
    }

    $SQL .= $Self->{CustomerCompanyKey};

    if ( !$Self->{ForeignDB} ) {
        $SQL .= ", change_time, create_time";
    }

    # this seems to be legacy, if Name is passed it should take precedence over CustomerID
    my $CustomerID = $Param{Name} || $Param{CustomerID};

    $SQL .= " FROM $Self->{CustomerCompanyTable} WHERE ";
    my $CustomerIDQuoted = $Self->{DBObject}->Quote($CustomerID);
    if ( $Self->{CaseSensitive} ) {
        $SQL .= "$Self->{CustomerCompanyKey} = '$CustomerIDQuoted'";
    }
    else {
        $SQL .= "LOWER($Self->{CustomerCompanyKey}) = LOWER('$CustomerIDQuoted')";
    }
    $SQL = $Self->_ConvertTo($SQL);

    # get initial data
    $Self->{DBObject}->Prepare( SQL => $SQL );

    # fetch the result
    my %Data;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {

        my $MapCounter = 0;

        for my $Entry ( @{ $Self->{CustomerCompanyMap} } ) {
            $Data{ $Entry->[0] } = $Self->_ConvertFrom( $Row[$MapCounter] );
            $MapCounter++;
        }

        $MapCounter++;
        $Data{ChangeTime} = $Row[$MapCounter];
        $MapCounter++;
        $Data{CreateTime} = $Row[$MapCounter];
    }

    return %Data;
}

=item CustomerCompanyUpdate()

update customer company attributes

    $CustomerCompanyObject->CustomerCompanyUpdate(
        CustomerCompanyID       => 'oldexample.com', #required if CustomerCompanyID-update
        CustomerID              => 'example.com',
        CustomerCompanyName     => 'New Customer Company Inc.',
        CustomerCompanyStreet   => '5201 Blue Lagoon Drive',
        CustomerCompanyZIP      => '33126',
        CustomerCompanyLocation => 'Miami',
        CustomerCompanyCountry  => 'USA',
        CustomerCompanyComment  => 'some comment',
        ValidID                 => 1,
        UserID                  => 123,
    );

=cut

sub CustomerCompanyUpdate {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    for my $Entry ( @{ $Self->{CustomerCompanyMap} } ) {
        if ( !$Param{ $Entry->[0] } && $Entry->[4] && $Entry->[0] ne 'UserPassword' ) {
            $Self->{LogObject}->Log(
                Priority => 'error',
                Message  => "Need $Entry->[0]!"
            );
            return;
        }
    }

    $Param{CustomerCompanyID} ||= $Param{CustomerID};

    # update db
    my $SQL = "UPDATE $Self->{CustomerCompanyTable} SET ";
    my $FieldInserted;

    for my $Entry ( @{ $Self->{CustomerCompanyMap} } ) {

        $SQL .= ', ' if $FieldInserted;
        if ( $Entry->[5] =~ /^int$/i ) {
            $SQL .= " $Entry->[2] = " . $Self->{DBObject}->Quote( $Param{ $Entry->[0] } );
        }
        elsif ( $Entry->[0] !~ /^UserPassword$/i ) {
            $SQL .= " $Entry->[2] = '" . $Self->{DBObject}->Quote( $Param{ $Entry->[0] } ) . "'";
        }
        $FieldInserted = 1;
    }

    if ( !$Self->{ForeignDB} ) {
        $SQL .= ", change_time = current_timestamp, change_by = $Param{UserID} ";
    }

    $SQL .= " WHERE $Self->{Lower}($Self->{CustomerCompanyKey}) = $Self->{Lower}('"
        . $Self->{DBObject}->Quote( $Param{CustomerCompanyID} ) . "')";
    $SQL = $Self->_ConvertTo($SQL);
    return if !$Self->{DBObject}->Do( SQL => $SQL );

    # log notice
    $Self->{LogObject}->Log(
        Priority => 'notice',
        Message =>
            "CustomerCompany: '$Param{CustomerCompanyName}/$Param{CustomerID}' updated successfully ($Param{UserID})!",
    );

    # open question:
    # should existing customer users and tickets be updated as well?
    # problem could be solved with a post-company-update-event

    return 1;
}

=item CustomerCompanyList()

get list of customer companies.

    my %List = $CustomerCompanyObject->CustomerCompanyList();

    my %List = $CustomerCompanyObject->CustomerCompanyList(
        Valid => 0,
    );

    my %List = $ProjectObject->ProjectList(
        Search => '*sometext*',
        Limit  => 10,
    );

Returns:

%List = {
          'example.com' => 'example.com Customer Company Inc.        ',
          'acme.com'    => 'acme.com Acme, Inc.        '
        };

=cut

sub CustomerCompanyList {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    my $Valid = 1;
    if ( !$Param{Valid} && defined( $Param{Valid} ) ) {
        $Valid = 0;
    }

    # what is the result
    my $What = '';
    for ( @{ $Self->{ConfigObject}->Get('CustomerCompany')->{CustomerCompanyListFields} } ) {

        if ($What) {
            $What .= ', ';
        }

        $What .= "$_";
    }

    # add valid option if required
    my $SQL = '';
    if ($Valid) {
        $SQL
            .= "$Self->{CustomerCompanyValid} IN ( ${\(join ', ', $Self->{ValidObject}->ValidIDsGet())} )";
    }

    # where
    if ( $Param{Search} ) {

        my $Count = 0;
        my @Parts = split /\+/, $Param{Search}, 6;

        for my $Part (@Parts) {

            $Part = $Self->{SearchPrefix} . $Part . $Self->{SearchSuffix};
            $Part =~ s/\*/%/g;
            $Part =~ s/%%/%/g;

            if ( $Count || $SQL ) {
                $SQL .= " AND ";
            }

            $Count++;

            my $CustomerCompanySearchFields
                = $Self->{ConfigObject}->Get('CustomerCompany')->{CustomerCompanySearchFields};

            if ( $CustomerCompanySearchFields && ref $CustomerCompanySearchFields eq 'ARRAY' ) {

                my $SQLExt = '';

                for ( @{$CustomerCompanySearchFields} ) {

                    if ($SQLExt) {
                        $SQLExt .= ' OR ';
                    }
                    $SQLExt .= " $Self->{Lower}($_) LIKE $Self->{Lower}('"
                        . $Self->{DBObject}->Quote($Part) . "') ";
                }

                if ($SQLExt) {
                    $SQL .= "($SQLExt)";
                }
            }
            else {
                $SQL .= " $Self->{Lower}($Self->{CustomerCompanyKey}) LIKE $Self->{Lower}('"
                    . $Self->{DBObject}->Quote($Part) . "') ";
            }
        }
    }

    # sql
    my $CompleteSQL = "SELECT $Self->{CustomerCompanyKey}, $What FROM $Self->{CustomerCompanyTable}";
    $CompleteSQL .= $SQL ? " WHERE $SQL" : '';
    $SQL = $Self->_ConvertTo($SQL);

    # ask database
    $Self->{DBObject}->Prepare(
        SQL   => $CompleteSQL,
        Limit => 50000,
    );

    # fetch the result
    my %List;
    while ( my @Row = $Self->{DBObject}->FetchrowArray() ) {

        my $Value = '';

        for my $Position ( 1 .. 10 ) {

            if ($Value) {
                $Value .= ' ';
            }

            if ( defined $Row[$Position] ) {
                $Value .= $Self->_ConvertFrom( $Row[$Position] );
            }
        }

        $List{ $Row[0] } = $Value;
    }

    return %List;
}

sub DESTROY {
    my $Self = shift;

    return 1 if !$Self->{NotParentDBObject};
    return 1 if !$Self->{DBObject};

    # disconnect if it's not a parent DBObject
    $Self->{DBObject}->Disconnect();

    return 1;
}

sub _ConvertFrom {
    my ( $Self, $Text ) = @_;

    return if !defined $Text;

    if ( !$Self->{SourceCharset} || !$Self->{DestCharset} ) {
        return $Text;
    }
    return $Self->{EncodeObject}->Convert(
        Text  => $Text,
        From  => $Self->{SourceCharset},
        To    => $Self->{DestCharset},
        Force => $Self->{CharsetConvertForce},
    );
}

sub _ConvertTo {
    my ( $Self, $Text ) = @_;

    return if !defined $Text;

    if ( !$Self->{SourceCharset} || !$Self->{DestCharset} ) {
        $Self->{EncodeObject}->EncodeInput( \$Text );
        return $Text;
    }
    return $Self->{EncodeObject}->Convert(
        Text  => $Text,
        To    => $Self->{SourceCharset},
        From  => $Self->{DestCharset},
        Force => $Self->{CharsetConvertForce},
    );
}

1;

=back

=head1 TERMS AND CONDITIONS

This software is part of the OTRS project (L<https://otrs.org/>).

This software comes with ABSOLUTELY NO WARRANTY. For details, see
the enclosed file COPYING for license information (GPL). If you
did not receive this file, see L<https://www.gnu.org/licenses/gpl-3.0.txt>.

=cut

=cut
