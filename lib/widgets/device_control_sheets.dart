import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/app_theme.dart';

// ─────────────────────────────────────────
//  Fan Control Bottom Sheet
// ─────────────────────────────────────────
class FanControlSheet extends StatefulWidget {
  final bool isActive;
  final int speed;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<int> onSpeedChanged;

  const FanControlSheet({
    super.key,
    required this.isActive,
    required this.speed,
    required this.onActiveChanged,
    required this.onSpeedChanged,
  });

  @override
  State<FanControlSheet> createState() => _FanControlSheetState();
}

class _FanControlSheetState extends State<FanControlSheet> {
  late bool _isActive;
  late int _speed;

  @override
  void initState() {
    super.initState();
    _isActive = widget.isActive;
    _speed = widget.speed;
  }

  @override
  Widget build(BuildContext context) {
    return _ControlSheetWrapper(
      title: 'Ceiling Fan',
      icon: FontAwesomeIcons.fan,
      isActive: _isActive,
      onActiveChanged: (val) {
        setState(() => _isActive = val);
        widget.onActiveChanged(val);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 24),
          Text(
            'FAN SPEED',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(letterSpacing: 3, fontSize: 11),
          ),
          const SizedBox(height: 20),
          // Speed Buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (i) {
              final speed = i + 1;
              final isSelected = _speed == speed;
              return GestureDetector(
                    onTap: _isActive
                        ? () {
                            setState(() => _speed = speed);
                            widget.onSpeedChanged(speed);
                          }
                        : null,
                    child: AnimatedContainer(
                      duration: 200.ms,
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected && _isActive
                            ? AppColors.accentGold
                            : AppColors.backgroundNavy,
                        border: Border.all(
                          color: isSelected && _isActive
                              ? AppColors.accentGold
                              : AppColors.textSecondary.withOpacity(0.3),
                          width: 1.5,
                        ),
                        boxShadow: isSelected && _isActive
                            ? [
                                BoxShadow(
                                  color: AppColors.accentGold.withOpacity(0.4),
                                  blurRadius: 12,
                                  spreadRadius: 1,
                                ),
                              ]
                            : [],
                      ),
                      child: Center(
                        child: Text(
                          '$speed',
                          style: TextStyle(
                            color: isSelected && _isActive
                                ? AppColors.backgroundNavy
                                : _isActive
                                ? AppColors.textMain
                                : AppColors.textSecondary,
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ),
                  )
                  .animate(target: isSelected && _isActive ? 1 : 0)
                  .scale(
                    begin: const Offset(1, 1),
                    end: const Offset(1.1, 1.1),
                    duration: 150.ms,
                  );
            }),
          ),
          const SizedBox(height: 28),
          // Speed label
          Center(
            child: AnimatedDefaultTextStyle(
              duration: 200.ms,
              style: TextStyle(
                color: _isActive
                    ? AppColors.accentGold
                    : AppColors.textSecondary,
                fontSize: 28,
                fontWeight: FontWeight.bold,
                letterSpacing: 2,
              ),
              child: Text(_isActive ? 'SPEED  $_speed' : 'OFFLINE'),
            ),
          ),
          const SizedBox(height: 8),
          // Mode row
          const SizedBox(height: 24),
          Text(
            'TIMER',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(letterSpacing: 3, fontSize: 11),
          ),
          const SizedBox(height: 12),
          _TimerRow(enabled: _isActive),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  AC Control Bottom Sheet
// ─────────────────────────────────────────
class AcControlSheet extends StatefulWidget {
  final bool isActive;
  final double temperature;
  final String mode;
  final ValueChanged<bool> onActiveChanged;
  final ValueChanged<double> onTemperatureChanged;
  final ValueChanged<String> onModeChanged;

  const AcControlSheet({
    super.key,
    required this.isActive,
    required this.temperature,
    required this.mode,
    required this.onActiveChanged,
    required this.onTemperatureChanged,
    required this.onModeChanged,
  });

  @override
  State<AcControlSheet> createState() => _AcControlSheetState();
}

class _AcControlSheetState extends State<AcControlSheet> {
  late bool _isActive;
  late double _temperature;
  late String _mode;

  final List<Map<String, dynamic>> _modes = [
    {'label': 'Cool', 'icon': FontAwesomeIcons.snowflake},
    {'label': 'Heat', 'icon': FontAwesomeIcons.sun},
    {'label': 'Auto', 'icon': FontAwesomeIcons.rotate},
    {'label': 'Fan', 'icon': FontAwesomeIcons.wind},
  ];

  @override
  void initState() {
    super.initState();
    _isActive = widget.isActive;
    _temperature = widget.temperature;
    _mode = widget.mode;
  }

  @override
  Widget build(BuildContext context) {
    return _ControlSheetWrapper(
      title: 'Living AC',
      icon: FontAwesomeIcons.snowflake,
      isActive: _isActive,
      onActiveChanged: (val) {
        setState(() => _isActive = val);
        widget.onActiveChanged(val);
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 28),
          // Big temperature display
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                IconButton(
                  onPressed: _isActive && _temperature > 16
                      ? () {
                          setState(() => _temperature -= 0.5);
                          widget.onTemperatureChanged(_temperature);
                        }
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                  color: AppColors.accentGold,
                  iconSize: 28,
                ),
                const SizedBox(width: 8),
                AnimatedDefaultTextStyle(
                  duration: 200.ms,
                  style: TextStyle(
                    color: _isActive
                        ? AppColors.accentGold
                        : AppColors.textSecondary,
                    fontSize: 72,
                    fontWeight: FontWeight.bold,
                    height: 1,
                  ),
                  child: Text(_temperature.toStringAsFixed(1)),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    '°C',
                    style: TextStyle(
                      color: _isActive
                          ? AppColors.accentGold
                          : AppColors.textSecondary,
                      fontSize: 28,
                      fontWeight: FontWeight.w300,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _isActive && _temperature < 30
                      ? () {
                          setState(() => _temperature += 0.5);
                          widget.onTemperatureChanged(_temperature);
                        }
                      : null,
                  icon: const Icon(Icons.add_rounded),
                  color: AppColors.accentGold,
                  iconSize: 28,
                ),
              ],
            ),
          ),
          // Slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: _isActive
                  ? AppColors.accentGold
                  : AppColors.textSecondary,
              inactiveTrackColor: AppColors.backgroundNavy,
              thumbColor: _isActive
                  ? AppColors.accentGold
                  : AppColors.textSecondary,
              overlayColor: AppColors.accentGold.withOpacity(0.15),
              trackHeight: 3,
            ),
            child: Slider(
              value: _temperature,
              min: 16,
              max: 30,
              divisions: 28,
              onChanged: _isActive
                  ? (val) {
                      setState(() => _temperature = val);
                      widget.onTemperatureChanged(val);
                    }
                  : null,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '16°C',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
              Text(
                '30°C',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            'MODE',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(letterSpacing: 3, fontSize: 11),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: _modes.map((m) {
              final isSelected = _mode == m['label'];
              return GestureDetector(
                onTap: _isActive
                    ? () {
                        setState(() => _mode = m['label'] as String);
                        widget.onModeChanged(_mode);
                      }
                    : null,
                child: AnimatedContainer(
                  duration: 200.ms,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected && _isActive
                        ? AppColors.accentGold.withOpacity(0.15)
                        : AppColors.backgroundNavy,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected && _isActive
                          ? AppColors.accentGold
                          : AppColors.textSecondary.withOpacity(0.2),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    children: [
                      FaIcon(
                        m['icon'] as IconData,
                        size: 18,
                        color: isSelected && _isActive
                            ? AppColors.accentGold
                            : AppColors.textSecondary,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        m['label'] as String,
                        style: TextStyle(
                          color: isSelected && _isActive
                              ? AppColors.accentGold
                              : AppColors.textSecondary,
                          fontSize: 11,
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  Shared wrapper for all control sheets
// ─────────────────────────────────────────
class _ControlSheetWrapper extends StatelessWidget {
  final String title;
  final IconData icon;
  final bool isActive;
  final ValueChanged<bool> onActiveChanged;
  final Widget child;

  const _ControlSheetWrapper({
    required this.title,
    required this.icon,
    required this.isActive,
    required this.onActiveChanged,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surfaceNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          const SizedBox(height: 12),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.textSecondary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(height: 20),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isActive
                        ? AppColors.accentGold.withOpacity(0.15)
                        : AppColors.backgroundNavy,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isActive
                          ? AppColors.accentGold.withOpacity(0.5)
                          : Colors.transparent,
                    ),
                  ),
                  child: FaIcon(
                    icon,
                    color: isActive
                        ? AppColors.accentGold
                        : AppColors.textSecondary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppColors.textMain,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                      Text(
                        isActive ? 'Active' : 'Offline',
                        style: TextStyle(
                          color: isActive
                              ? AppColors.accentGold
                              : AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: isActive,
                    onChanged: onActiveChanged,
                    activeThumbColor: AppColors.accentGold,
                    activeTrackColor: AppColors.accentGold.withOpacity(0.25),
                    inactiveThumbColor: AppColors.textSecondary,
                    inactiveTrackColor: AppColors.backgroundNavy,
                  ),
                ),
              ],
            ),
          ),
          // Divider
          const SizedBox(height: 16),
          Divider(color: AppColors.textSecondary.withOpacity(0.12), height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: child,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────
//  Simple Timer Row widget
// ─────────────────────────────────────────
class _TimerRow extends StatefulWidget {
  final bool enabled;
  const _TimerRow({required this.enabled});

  @override
  State<_TimerRow> createState() => _TimerRowState();
}

class _TimerRowState extends State<_TimerRow> {
  final List<String> options = ['Off', '30m', '1h', '2h', '4h'];
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(options.length, (i) {
        final isSelected = _selected == i;
        return GestureDetector(
          onTap: widget.enabled ? () => setState(() => _selected = i) : null,
          child: AnimatedContainer(
            duration: 200.ms,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isSelected && widget.enabled
                  ? AppColors.accentGold
                  : AppColors.backgroundNavy,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isSelected && widget.enabled
                    ? AppColors.accentGold
                    : AppColors.textSecondary.withOpacity(0.2),
              ),
            ),
            child: Text(
              options[i],
              style: TextStyle(
                color: isSelected && widget.enabled
                    ? AppColors.backgroundNavy
                    : widget.enabled
                    ? AppColors.textMain
                    : AppColors.textSecondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ),
        );
      }),
    );
  }
}
