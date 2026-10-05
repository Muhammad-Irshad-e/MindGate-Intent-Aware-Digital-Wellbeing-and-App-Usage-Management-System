import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../services/analytics_service.dart';

class StatisticsScreen extends StatefulWidget {
  final VoidCallback? onBackToHome;

  const StatisticsScreen({super.key, this.onBackToHome});

  @override
  State<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends State<StatisticsScreen> with WidgetsBindingObserver {
  final UsageAnalyticsService _analyticsService = UsageAnalyticsService();
  int _selectedPeriodIndex = 0; // 0: Day, 1: Weekly, 2: Monthly
  DateTime _referenceDate = DateTime.now();

  StatisticsData? _data;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadStatisticsData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _loadStatisticsData();
    }
  }

  Future<void> _loadStatisticsData() async {
    if (_data == null) {
      setState(() => _isLoading = true);
    }
    final loaded = await _analyticsService.getStatisticsData(
      periodIndex: _selectedPeriodIndex,
      referenceDate: _referenceDate,
    );
    if (mounted) {
      setState(() {
        _data = loaded;
        _isLoading = false;
      });
    }
  }

  void _onPeriodChanged(int newIndex) {
    if (_selectedPeriodIndex != newIndex) {
      setState(() {
        _selectedPeriodIndex = newIndex;
        _referenceDate = DateTime.now();
      });
      _loadStatisticsData();
    }
  }

  void _navigateDate(int direction) {
    setState(() {
      if (_selectedPeriodIndex == 0) {
        _referenceDate = _referenceDate.add(Duration(days: direction));
      } else if (_selectedPeriodIndex == 1) {
        _referenceDate = _referenceDate.add(Duration(days: direction * 7));
      } else {
        _referenceDate = DateTime(
          _referenceDate.year,
          _referenceDate.month + direction,
          _referenceDate.day.clamp(1, 28),
        );
      }
    });
    _loadStatisticsData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Statistics'),
        leading: IconButton(
          icon: const Icon(Icons.chevron_left_rounded, size: 28),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else if (widget.onBackToHome != null) {
              widget.onBackToHome!();
            }
          },
        ),
      ),
      body: _isLoading || _data == null
          ? const Center(child: CircularProgressIndicator(color: AppColors.primaryGreen))
          : RefreshIndicator(
              onRefresh: _loadStatisticsData,
              color: AppColors.primaryGreen,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Period Toggle Tabs (Day / Weekly / Monthly)
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          _buildTabPill(0, 'Day'),
                          _buildTabPill(1, 'Weekly'),
                          _buildTabPill(2, 'Monthly'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Date Selector Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.border),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.chevron_left_rounded, color: AppColors.textSecondary),
                            onPressed: () => _navigateDate(-1),
                          ),
                          Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 16, color: AppColors.textSecondary),
                              const SizedBox(width: 8),
                              Text(
                                _data!.dateLabel,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            icon: const Icon(Icons.chevron_right_rounded, color: AppColors.textSecondary),
                            onPressed: () => _navigateDate(1),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // App Usage by Category Donut Chart Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'App Usage by Category',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                // Donut Chart
                                SizedBox(
                                  width: 140,
                                  height: 140,
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      PieChart(
                                        PieChartData(
                                          sectionsSpace: 2,
                                          centerSpaceRadius: 42,
                                          startDegreeOffset: -90,
                                          sections: _buildPieSections(_data!),
                                        ),
                                      ),
                                      Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            _data!.formattedTotalTime,
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w800,
                                              color: AppColors.textPrimary,
                                            ),
                                          ),
                                          const Text(
                                            'Total',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.textSecondary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 24),

                                // Legend on Right
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildLegendItem(
                                        color: AppColors.productive,
                                        label: 'Productive',
                                        percent: '${_data!.productivePercentage}%',
                                      ),
                                      const SizedBox(height: 12),
                                      _buildLegendItem(
                                        color: AppColors.neutral,
                                        label: 'Neutral',
                                        percent: '${_data!.neutralPercentage}%',
                                      ),
                                      const SizedBox(height: 12),
                                      _buildLegendItem(
                                        color: AppColors.negative,
                                        label: 'Negative',
                                        percent: '${_data!.negativePercentage}%',
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Usage Trend Bar Chart Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Usage Trend',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                _buildDropdownPill('App Usage'),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 140,
                              child: _buildBarChart(_data!),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // CPI Trend Line Chart Card
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'CPI Trend',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                _buildDropdownPill(
                                  _selectedPeriodIndex == 0
                                      ? 'Daily'
                                      : (_selectedPeriodIndex == 1 ? 'Last 7 Days' : 'Monthly'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 20),
                            SizedBox(
                              height: 140,
                              child: _buildLineChart(_data!),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
    );
  }

  List<PieChartSectionData> _buildPieSections(StatisticsData data) {
    if (data.cpiResult.totalDurationMs == 0) {
      return [
        PieChartSectionData(
          color: const Color(0xFFE2E8F0),
          value: 100,
          showTitle: false,
          radius: 20,
        )
      ];
    }

    return [
      if (data.productivePercentage > 0)
        PieChartSectionData(
          color: AppColors.productive,
          value: data.productivePercentage.toDouble(),
          showTitle: false,
          radius: 20,
        ),
      if (data.neutralPercentage > 0)
        PieChartSectionData(
          color: AppColors.neutral,
          value: data.neutralPercentage.toDouble(),
          showTitle: false,
          radius: 20,
        ),
      if (data.negativePercentage > 0)
        PieChartSectionData(
          color: AppColors.negative,
          value: data.negativePercentage.toDouble(),
          showTitle: false,
          radius: 20,
        ),
    ];
  }

  Widget _buildBarChart(StatisticsData data) {
    final bars = data.usageTrendBars;
    double maxVal = 60.0;
    for (final b in bars) {
      if (b > maxVal) maxVal = b;
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        maxY: maxVal,
        barTouchData: const BarTouchData(enabled: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: maxVal / 2,
              getTitlesWidget: (val, meta) {
                if (val == 0) return const Text('0m', style: TextStyle(fontSize: 10, color: AppColors.textMuted));
                return Text('${val.toInt()}m', style: const TextStyle(fontSize: 10, color: AppColors.textMuted));
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx >= 0 && idx < data.barXLabels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      data.barXLabels[idx],
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        barGroups: List.generate(bars.length, (index) {
          return BarChartGroupData(
            x: index,
            barRods: [
              BarChartRodData(
                toY: bars[index],
                color: const Color(0xFF60A5FA),
                width: 14,
                borderRadius: BorderRadius.circular(4),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildLineChart(StatisticsData data) {
    final spots = data.cpiTrendSpots;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 100,
        gridData: FlGridData(
          show: true,
          horizontalInterval: 50,
          getDrawingHorizontalLine: (val) => FlLine(
            color: AppColors.border,
            strokeWidth: 1,
            dashArray: [4, 4],
          ),
          drawVerticalLine: false,
        ),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              interval: 50,
              getTitlesWidget: (val, meta) {
                return Text(
                  '${val.toInt()}',
                  style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                );
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (val, meta) {
                final idx = val.toInt();
                if (idx >= 0 && idx < data.lineXLabels.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      data.lineXLabels[idx],
                      style: const TextStyle(fontSize: 10, color: AppColors.textMuted),
                    ),
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: List.generate(
              spots.length,
              (i) => FlSpot(i.toDouble(), spots[i]),
            ),
            isCurved: true,
            color: AppColors.productive,
            barWidth: 3,
            isStrokeCapRound: true,
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, barData, index) {
                final isLast = index == spots.length - 1;
                return FlDotCirclePainter(
                  radius: isLast ? 5 : 3,
                  color: AppColors.productive,
                  strokeWidth: isLast ? 2 : 0,
                  strokeColor: Colors.white,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabPill(int index, String title) {
    final isSelected = _selectedPeriodIndex == index;
    return Expanded(
      child: GestureDetector(
        onTap: () => _onPeriodChanged(index),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.primaryGreen : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.white : AppColors.textSecondary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLegendItem({required Color color, required String label, required String percent}) {
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
          ),
        ),
        Text(
          percent,
          style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _buildDropdownPill(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.inputBackground,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: AppColors.textSecondary),
        ],
      ),
    );
  }
}
