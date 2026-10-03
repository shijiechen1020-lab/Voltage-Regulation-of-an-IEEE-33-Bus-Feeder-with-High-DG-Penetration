function plot_results()
% PLOT_RESULTS  Plot the OpenDSS results of the four IEEE 33-bus scenarios.
%
% Reads the CSV files exported by the OpenDSS scripts (../results) and saves
% these figures to ../figures:
%   <n>_<scenario>_voltage.png       bus voltage profile
%   <n>_<scenario>_power_flow.png    active and reactive power on each line
%   <n>_<scenario>_line_losses.png   active power loss of each line
%   0_voltage_comparison.png         voltage profiles of all four scenarios
% It also prints a summary table to the Command Window: total losses, grid
% import, minimum and maximum voltage, and the number of buses below 0.95 and
% above 1.05 p.u.
%
% Usage: open this file in MATLAB and press Run, or type plot_results.

here       = fileparts(mfilename('fullpath'));
resultsDir = fullfile(here, '..', 'results');
figDir     = fullfile(here, '..', 'figures');
if ~exist(figDir, 'dir')
    mkdir(figDir);
end

% CSV prefix, figure prefix, title, short name for the comparison legend
scenarios = {
    'S1_Base',      '1_base',      'Scenario 1: base case (no DG)',             '1 Base case'
    'S2_HighDG',    '2_high_dg',   'Scenario 2: high DG penetration (61.37 %)', '2 High DG'
    'S3_Strategy1', '3_strategy1', 'Scenario 3: PV curtailment + capacitor',    '3 Curtailment + capacitor'
    'S4_SOP',       '4_sop',       'Scenario 4: soft open point (SOP)',         '4 SOP'
};
nScen = size(scenarios, 1);
allV  = zeros(33, nScen);

fprintf('\n%-42s %11s %10s %18s %18s %7s %7s\n', 'Scenario', 'Losses(kW)', ...
    'Grid(kW)', 'Vmin (p.u.)', 'Vmax (p.u.)', '<0.95', '>1.05');

for s = 1:nScen
    csvPrefix = fullfile(resultsDir, scenarios{s, 1});
    figPrefix = fullfile(figDir, scenarios{s, 2});
    label     = scenarios{s, 3};

    V                  = read_voltages([csvPrefix '_Voltages.csv']);
    [P, Q, gridP]      = read_line_flows([csvPrefix '_Powers.csv']);
    [lineLoss, trLoss] = read_losses([csvPrefix '_Losses.csv']);
    allV(:, s) = V;

    plot_voltage(V, label, [figPrefix '_voltage.png']);
    plot_flows(P, Q, label, [figPrefix '_power_flow.png']);
    plot_losses(lineLoss, trLoss, label, [figPrefix '_line_losses.png']);

    [vMin, iMin] = min(V);
    [vMax, iMax] = max(V);
    fprintf('%-42s %11.1f %10.0f %8.3f (bus %2d) %8.3f (bus %2d) %7d %7d\n', label, ...
        sum(lineLoss) + trLoss, gridP, vMin, iMin, vMax, iMax, sum(V < 0.95), sum(V > 1.05));
end

plot_comparison(allV, scenarios(:, 4), fullfile(figDir, '0_voltage_comparison.png'));
fprintf('\nFigures saved to %s\n', figDir);
end


%% ---------- Reading the OpenDSS CSV exports ----------

function [header, rows] = read_dss_csv(file)
% Split an OpenDSS CSV export into its header and rows of text fields.
% Rows can have different lengths, so each row is kept as its own cell array.
text  = fileread(file);
lines = regexp(text, '\r?\n', 'split');
lines = lines(~cellfun(@(s) isempty(strtrim(s)), lines));
header = strtrim(regexp(lines{1}, ',', 'split'));
rows   = cell(numel(lines) - 1, 1);
for k = 2:numel(lines)
    fields = regexp(lines{k}, ',', 'split');
    rows{k - 1} = strtrim(strrep(fields, '"', ''));
end
end

function V = read_voltages(file)
% Per-unit voltage at buses 1-33 (mean of the three phases).
[header, rows] = read_dss_csv(file);
puCols = find(~cellfun(@isempty, regexp(header, '^pu\d+$')));
V = nan(33, 1);
for k = 1:numel(rows)
    bus = str2double(rows{k}{1});   % the 110 kV SOURCEBUS gives NaN and is skipped
    if bus >= 1 && bus <= 33
        V(bus) = mean(str2double(rows{k}(puCols)));
    end
end
end

function [P, Q, gridP] = read_line_flows(file)
% Active (kW) and reactive (kvar) power at the upstream end (terminal 1) of
% each line, and the active power drawn from the grid through the transformer.
[header, rows] = read_dss_csv(file);
cElem = find(strcmp(header, 'Element'));
cTerm = find(strcmp(header, 'Terminal'));
cP    = find(strcmp(header, 'P(kW)'));
cQ    = find(strcmp(header, 'Q(kvar)'));
P = nan(32, 1);
Q = nan(32, 1);
gridP = NaN;
for k = 1:numel(rows)
    r = rows{k};
    if str2double(r{cTerm}) ~= 1
        continue                     % keep terminal 1 (upstream end) only
    end
    tok = regexpi(r{cElem}, '^Line\.L(\d+)$', 'tokens', 'once');
    if ~isempty(tok)
        n = str2double(tok{1});
        P(n) = str2double(r{cP});
        Q(n) = str2double(r{cQ});
    elseif strcmpi(r{cElem}, 'Transformer.SubTrans')
        gridP = str2double(r{cP});
    end
end
end

function [lineLoss, trLoss] = read_losses(file)
% Active power loss (kW) of each line and of the substation transformer.
[header, rows] = read_dss_csv(file);
cElem = find(strcmp(header, 'Element'));
cLoss = find(strcmp(header, 'Total(W)'));
lineLoss = nan(32, 1);
trLoss = NaN;
for k = 1:numel(rows)
    r = rows{k};
    tok = regexpi(r{cElem}, '^Line\.L(\d+)$', 'tokens', 'once');
    if ~isempty(tok)
        lineLoss(str2double(tok{1})) = str2double(r{cLoss}) / 1000;
    elseif strcmpi(r{cElem}, 'Transformer.SubTrans')
        trLoss = str2double(r{cLoss}) / 1000;
    end
end
end


%% ---------- Plotting ----------

function plot_voltage(V, label, file)
fig = new_figure([900 480]);
setup_voltage_axes();
plot_feeder(V, 'o-', [0 0.447 0.741]);
title(label);
save_figure(fig, file);
end

function plot_comparison(allV, labels, file)
fig = new_figure([900 560]);
setup_voltage_axes();
colors = [0 0.447 0.741; 0.850 0.325 0.098; 0.466 0.674 0.188; 0.494 0.184 0.556];
styles = {'o-', 's-', '^-', 'd-'};
h = [];
for s = 1:size(allV, 2)
    h = [h, plot_feeder(allV(:, s), styles{s}, colors(s, :))]; %#ok<AGROW>
end
legend(h, labels, 'Location', 'southoutside', 'Orientation', 'horizontal');
title('Bus voltage profiles of the four scenarios');
save_figure(fig, file);
end

function plot_flows(P, Q, label, file)
fig = new_figure([900 560]);
subplot(2, 1, 1);
bar(1:32, P, 'FaceColor', [0 0.447 0.741]);
grid on; box on; xlim([0 33]);
ylabel('Active power (kW)');
title({label, 'Power at the upstream end of each line (negative = reverse flow)'});
subplot(2, 1, 2);
bar(1:32, Q, 'FaceColor', [0.850 0.325 0.098]);
grid on; box on; xlim([0 33]);
ylabel('Reactive power (kvar)');
xlabel('Line number (line k feeds bus k+1)');
save_figure(fig, file);
end

function plot_losses(lineLoss, trLoss, label, file)
fig = new_figure([900 420]);
bar(1:32, lineLoss, 'FaceColor', [0.850 0.325 0.098]);
grid on; box on; xlim([0 33]);
xlabel('Line number (line k feeds bus k+1)');
ylabel('Active power loss (kW)');
title({label, sprintf('Lines %.1f kW + transformer %.1f kW = %.1f kW total', ...
    sum(lineLoss), trLoss, sum(lineLoss) + trLoss)});
save_figure(fig, file);
end

function setup_voltage_axes()
% Common axes for the voltage plots: limits, branch boundaries and labels.
hold on; grid on; box on;
xlim([0 34]);
ylim([0.90 1.08]);
plot([0 34], [1.05 1.05], 'r--', 'LineWidth', 1);
plot([0 34], [0.95 0.95], 'r--', 'LineWidth', 1);
text(0.3, 1.05, 'Upper limit 1.05', 'Color', 'r', 'VerticalAlignment', 'bottom');
text(0.3, 0.95, 'Lower limit 0.95', 'Color', 'r', 'VerticalAlignment', 'top');
grey = [0.45 0.45 0.45];
for xb = [18.5 22.5 25.5]
    plot([xb xb], [0.90 1.08], ':', 'Color', grey);
end
names   = {'Main feeder', 'Lateral', 'Lateral', 'Lateral'};
centres = [9.5 20.5 24 29.75];
for i = 1:numel(names)
    text(centres(i), 1.074, names{i}, 'Color', grey, 'HorizontalAlignment', 'center');
end
xlabel('Bus number');
ylabel('Voltage (p.u.)');
end

function h = plot_feeder(V, style, color)
% Plot each branch as its own line so the laterals are not joined to the
% end of the main feeder (bus 18 -> 19, 22 -> 23, 25 -> 26).
x = [1:18, NaN, 19:22, NaN, 23:25, NaN, 26:33];
y = nan(size(x));
y(~isnan(x)) = V(x(~isnan(x)));
h = plot(x, y, style, 'Color', color, 'LineWidth', 1.5, ...
    'MarkerSize', 4, 'MarkerFaceColor', color);
end

function fig = new_figure(sizePx)
fig = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 sizePx]);
try
    theme(fig, 'light');   % R2025a+: keep dark text even if MATLAB uses a dark theme
catch
    % theme() does not exist before R2025a; figures are light there anyway
end
end

function save_figure(fig, file)
set(fig, 'PaperPositionMode', 'auto');
print(fig, file, '-dpng', '-r150');
close(fig);
end
