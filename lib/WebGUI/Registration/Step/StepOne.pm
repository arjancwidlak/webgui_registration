package WebGUI::Registration::Step::StepOne;

use strict;

use base qw{ WebGUI::Registration::Step };

#-------------------------------------------------------------------
sub getStepForm {
    my $self    = shift;

    my $f = $self->SUPER::getStepForm;
    $f->yesNo(
        -name   => 'hopsa',
        -value  => 0,
        -label  => 'Compleet?',
    );
    $f->submit;

    return $f;
}

#-------------------------------------------------------------------
sub processStepFormData {
    my $self    = shift;

    my $proceed = $self->session->form->process('hopsa');

    $self->{_hopsa} = $proceed;
}

#-------------------------------------------------------------------
sub isComplete {
    my $self = shift;

    return $self->{_hopsa};
}

#-------------------------------------------------------------------
sub view {
    return 'Step 1';
}

1;
