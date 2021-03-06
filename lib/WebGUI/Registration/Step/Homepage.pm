package WebGUI::Registration::Step::Homepage;

use strict;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub apply {
    my $self = shift;

    $self->installUserPage({
        packageId   => $self->session->form->process('packageId')
    });
}

#-------------------------------------------------------------------
sub crud_definition {
    my $class       = shift;
    my $session     = shift;
    my $definition  = $class->SUPER::crud_definition( $session );
    my $i18n        = WebGUI::International->new( $session, 'Registration' );

    # Create a hash containing all profile fields of the form: ID => Category::FieldName.
    tie my %profileFields, 'Tie::IxHash',
        ''  => '--- Do not store ---',
        map { $_->getId => $_->getCategory->getLabel . '::' . $_->getLabel }
            @{ WebGUI::ProfileField->getFields($session) };

    $definition->{ dynamic }->{ userPageContainer   } = {
        fieldType       => 'asset',
        tab             => 'properties',
        label           => $i18n->echo('Put user pages on'),
    };
    $definition->{ dynamic }->{ packageContainer    } = {
        fieldType       => 'asset',
        tab             => 'properties',
        label           => $i18n->echo('Fetch packages from'),
    };
    $definition->{ dynamic }->{ makeUserPageOwner   } = {
        fieldType       => 'yesNo',
        tab             => 'properties',
        label           => $i18n->echo('Make user owner of his pages'),
    };
    $definition->{ dynamic }->{ urlStorageField     } = {
        fieldType       => 'selectBox',
        label           => 'Store homepage url in field',
        options         => \%profileFields,
    };

    return $definition;
}

#-------------------------------------------------------------------
sub exports {
    my $self    = shift;
    my $exports = $self->SUPER::exports;

    push @{ $exports }, {
        name    => 'deployedPageRoot',
        type    => 'assetId',
        label   => 'Root of deployed pages',
    };

    return $exports;
}

#-------------------------------------------------------------------
sub getEditForm {
    my $self    = shift;
    my $session = $self->session;

    my $tabform = $self->SUPER::getEditForm;
    $tabform->getTab('properties')->readOnly(
        -label  => 'Edit group',
        -value  =>
            WebGUI::Form::group( $session, {
                name    => 'editGroupId',
                value   => $self->get('editGroupId') || $session->form->process('editGroupId'),
            })
            . $self->getExportVariablesSelectBox( 'editGroupId_export', 'groupId' ),
    );

    return $tabform;
}

#-------------------------------------------------------------------
sub getSummaryTemplateVars {
    my $self                    = shift;
    my $includeAdminControls    = shift;
    my $session                 = $self->session;
    my @fields;

    # Fetch preferred homepage url
    my $preferredHomepageUrl = $self->getConfigurationData->{ preferredHomepageUrl };

    # Fetch available packages
    my $packageContainer = WebGUI::Asset->newByDynamicClass($self->session, $self->get('packageContainer'));
    my %packageList = map { $_->getId => $_->get('title') } @{ $packageContainer->getLineage(['children'], {
        returnObjects   => 1,
        whereClause     => 'assetData.isPackage = 1',
    })};

    # Preferred homepage url
    push @fields, {
        field_label         => 'Your homepage',
        field_value         => $preferredHomepageUrl,
        field_formElement   => WebGUI::Form::text( $session,  {
            name    => 'preferredHomepageUrl',
            value   => $preferredHomepageUrl,
        }),
    };
    # Package to deploy
    push @fields, {
        field_label         => 'Choose package',
        field_value         => $session->form->process('packageId') || '',
        field_formElement   => WebGUI::Form::selectBox( $session, {
            name    => 'packageId',
            value   => [ $session->form->process('packageId') ],
            options => \%packageList,
        }),
    } if $includeAdminControls;

    # Setup tmpl_var
    my $var = {
        field_loop          => \@fields,
        category_label      => $self->get('title'),
        category_edit_url   => $self->changeStepDataUrl,
    };

    return ( $var );
}

#-------------------------------------------------------------------
sub getViewVars {
    my $self = shift;

    my $var = $self->SUPER::getViewVars;

    my $preferredHomepageUrl =
        $self->session->form->process('preferredHomepageUrl')
        || $self->getConfigurationData->{'preferredHomepageUrl'};

    push @{ $var->{ field_loop } }, (
        {
            field_label         => 'www.wieismijnarts.nl/',
            field_formElement   =>
                WebGUI::Form::text($self->session, {
                    name    => 'preferredHomepageUrl',
                    value   => $preferredHomepageUrl
                }),
#           field_subtext   => 'Hier komt de subtext voor dit veld'
        }
    );

    return $var;
}

#-------------------------------------------------------------------
sub installUserPage {
    my $self        = shift;
    my $parameters  = shift;

    my $user        = $self->registration->instance->user;
    my $session     = $self->session;

    my $userGroup;

    # Deploy package under a seperate version tag.

    #### TODO: Check if a user object has been instanciated.

    # Deploy package
    my $userPageRoot = WebGUI::Asset->newByDynamicClass( $session, $self->get('userPageContainer') );

    #### TODO: Complain if $userPageRoot does not exist.

    my $packageMasterAsset  = WebGUI::Asset->newByDynamicClass( $session, $parameters->{packageId} );
    my $masterLineage       = $packageMasterAsset->get("lineage");

    if (defined $packageMasterAsset && $self->get("lineage") !~ /^$masterLineage/) {
        my $userGroupId = $self->getExportVariable( $self->get('editGroupId_export') ) || $self->get('editGroupId');

        my $assetProperties = {};
        # Set privileges of deployed package;
        if ($self->get('makeUserPageOwner')) {
            $assetProperties->{ownerUserId} = $user->userId;
#            $assetProperties->{groupIdView} = $groupIdView;
            $assetProperties->{groupIdEdit} = $userGroupId if ($userGroupId);
        }

        #### NOTE: $fullName is used to replace the title and menuTitle of the root of the deployed asset.
        ####       This is hardcoded for now. Therefore the first, middle and lastName must be entered.
        my $fullName = join(' ', (
            $user->profileField('firstName'),
            $user->profileField('middleName'),
            $user->profileField('lastName')
        ));

        # Figure out the root url of the deployed package.
        my $deployedPackageRootUrl =
               $self->getConfigurationData->{ preferredHomepageUrl }
            || $user->profileField('firstName') . $user->profileField('middleName') . $user->profileField('lastName');

        # Deploy package under userPageRoot
		my $deployedTreeMaster = $packageMasterAsset->duplicateBranch;
		$deployedTreeMaster->setParent($userPageRoot);
		$deployedTreeMaster->update({
            isPackage   => 0,
            url         => $deployedPackageRootUrl,
            title       => $fullName,
            menuTitle   => $fullName,

            %$assetProperties,
        }); #, styleTemplateId=>$self->get("styleTemplateId")});

        # Store the root url in the user profile
        if ( $self->get('urlStorageField') ) {
            $user->profileField($self->get('urlStorageField'), $deployedTreeMaster->getUrl);
        }

        # Set urls of deployed package
        my $updatePages = $deployedTreeMaster->getLineage( ['descendants'], {returnObjects => 1} );
        foreach my $currentAsset (@$updatePages) {
            # Figure out correct url
            $assetProperties->{url} = $currentAsset->getParent->get('url') . '/' . $currentAsset->get('menuTitle');

            if ($currentAsset->get('className') =~ m/^WebGUI::Asset::Wobject::Collaboration/ && $userGroupId) {
                $assetProperties->{postGroupId} = $userGroupId;
                $assetProperties->{canStartThreadGroupId} = $userGroupId;
            }

            # Apply overrides
            $currentAsset->update({ %$assetProperties });
        }

        $self->setExportVariable( 'deployedPageRoot', $deployedTreeMaster->getId );
        $self->setConfigurationData( 'deployedPageRoot', $deployedTreeMaster->getId );
    }


}


#-------------------------------------------------------------------
sub isComplete {
    my $self = shift;

    return defined $self->getConfigurationData->{'preferredHomepageUrl'};
}

#-------------------------------------------------------------------
sub onDeleteAccount {
    my $self    = shift;
    my $doit    = shift;
    my $session = $self->session;
    my $output;

    # Delete user homepage
    my $userPageRootUrl = $self->registration->instance->user->profileField( $self->get('urlStorageField' ) );
    my $userPageRoot;

    if ( $userPageRootUrl ) {
        $userPageRoot   = WebGUI::Asset->newByUrl( $session, $userPageRootUrl );
    }
    else {
        $userPageRoot = WebGUI::Asset->newByDynamicClass( $session, $self->getConfigurationData->{ 'deployedPageRoot' } );
    }

    # Make really sure the asset we got is the correct one and not for instance the default 404 page.
#    if ( $userPageRoot->getId eq $self->getConfigurationData->{ 'deployedPageRoot' } ) {
    if ( $userPageRoot ) {
        $output = 'Homepage: '.$userPageRoot->getUrl;

        $userPageRoot->purge if $doit;
    }
    else {
        $output = 'Homepage: not found.';
    }

    $self->SUPER::onDeleteAccount( $doit );

    return $output;
}

#-------------------------------------------------------------------
sub updateFromFormPost {
    my $self    = shift;
    my $session = $self->session;

    $self->SUPER::updateFromFormPost;

    $self->update( {
        editGroupId         => $session->form->process('editGroupId'),
        editGroupId_export  => $session->form->process('editGroupId_export'),
    } );
}

#-------------------------------------------------------------------
sub processStepFormData {
    my $self    = shift;
    my $session = $self->session;

    my $url     = $session->form->process('preferredHomepageUrl');
    unless ( $url ) {
        $self->pushError( "De url is verplicht." );
    }
    if ( WebGUI::Asset->urlExists($session, $url) ) {
        $self->pushError( "De url $url is al bezet" );
    }

    return if @{ $self->error };
    # Store homepage url
    $self->setConfigurationData('preferredHomepageUrl', $url );
}

1;
