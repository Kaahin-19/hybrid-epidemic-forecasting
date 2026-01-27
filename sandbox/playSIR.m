%PLAYSIR Play with a SIR-model.

% S. Engblom 2026-01-27

% simulate a standard SIR-model with time-dependent R_t
umod = genData('SIRS');

% visualize it
figure, clf,
plot(umod.tspan,umod.U(2,:));
xlabel('Time [days]');
ylabel('Cases');
