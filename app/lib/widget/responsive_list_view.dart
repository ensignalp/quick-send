import 'package:flutter/material.dart';
import 'package:localsend_app/util/ui/nav_bar_padding.dart';
import 'package:localsend_app/widget/responsive_builder.dart';

class ResponsiveListView extends StatelessWidget {
  static const defaultMaxWidth = 600.0;

  final double maxWidth;
  final ScrollController? controller;
  final EdgeInsets padding;
  final EdgeInsets desktopPadding;
  final List<Widget>? children;
  final Widget? child;
  final int? itemCount;
  final IndexedWidgetBuilder? itemBuilder;

  const ResponsiveListView.single({
    this.maxWidth = defaultMaxWidth,
    this.controller,
    required this.padding,
    EdgeInsets? tabletPadding,
    required Widget this.child,
    super.key,
  }) : desktopPadding = tabletPadding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 30),
       children = null,
       itemCount = null,
       itemBuilder = null;

  const ResponsiveListView({
    this.maxWidth = defaultMaxWidth,
    this.controller,
    required this.padding,
    EdgeInsets? tabletPadding,
    required List<Widget> this.children,
    super.key,
  }) : desktopPadding = tabletPadding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 30),
       child = null,
       itemCount = null,
       itemBuilder = null;

  const ResponsiveListView.builder({
    this.maxWidth = defaultMaxWidth,
    this.controller,
    required this.padding,
    EdgeInsets? tabletPadding,
    required int this.itemCount,
    required IndexedWidgetBuilder this.itemBuilder,
    super.key,
  }) : desktopPadding = tabletPadding ?? const EdgeInsets.symmetric(horizontal: 10, vertical: 30),
       children = null,
       child = null;

  @override
  Widget build(BuildContext context) {
    if (itemBuilder != null) {
      return ResponsiveBuilder(
        builder: (sizingInformation) {
          final resolvedPadding = sizingInformation.isDesktop ? desktopPadding : padding;
          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: ListView.builder(
                controller: controller,
                padding: resolvedPadding.copyWith(
                  bottom: resolvedPadding.bottom + getNavBarPadding(context),
                ),
                itemCount: itemCount!,
                itemBuilder: itemBuilder!,
              ),
            ),
          );
        },
      );
    } else if (children != null) {
      return ResponsiveBuilder(
        builder: (sizingInformation) {
          final resolvedPadding = sizingInformation.isDesktop ? desktopPadding : padding;
          return SingleChildScrollView(
            controller: controller,
            child: Center(
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: maxWidth),
                child: Padding(
                  padding: resolvedPadding.copyWith(
                    bottom: resolvedPadding.bottom + getNavBarPadding(context),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children!,
                  ),
                ),
              ),
            ),
          );
        },
      );
    } else {
      return ResponsiveBuilder(
        builder: (sizingInformation) => Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: sizingInformation.isDesktop ? desktopPadding : padding,
              child: child!,
            ),
          ),
        ),
      );
    }
  }
}
