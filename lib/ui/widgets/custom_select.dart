// CustomSelect — faithful port of neomage/src/components/CustomSelect/
// Ports: Select, SelectOption, SelectInputOption, OptionMap,
// useSelectState, useSelectNavigation, useSelectInput, SelectMulti.
//
// Provides a configurable select/dropdown widget with:
// - Scrollable option list with keyboard navigation
// - Inline input options (type-to-filter)
// - Multi-select mode
// - Highlight text matching
// - Compact / expanded / compact-vertical layouts
// - Page up/down navigation

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sint/sint.dart';

// ─── Option model (port of select.tsx OptionWithDescription) ─────────────

/// An option in the select list.
class SelectOption<T> {
  final String? description;
  final bool dimDescription;
  final Widget label;
  final T value;
  final bool disabled;
  final SelectOptionType type;

  // Input-type specific fields
  final ValueChanged<String>? onInputChange;
  final String? placeholder;
  final String? initialValue;
  final bool allowEmptySubmitToCancel;
  final bool showLabelWithValue;
  final String labelValueSeparator;
  final bool resetCursorOnUpdate;

  const SelectOption({
    this.description,
    this.dimDescription = false,
    required this.label,
    required this.value,
    this.disabled = false,
    this.type = SelectOptionType.text,
    this.onInputChange,
    this.placeholder,
    this.initialValue,
    this.allowEmptySubmitToCancel = false,
    this.showLabelWithValue = false,
    this.labelValueSeparator = ', ',
    this.resetCursorOnUpdate = false,
  });
}

enum SelectOptionType { text, input }

// ─── Option map (port of option-map.ts) ──────────────────────────────────

/// Linked-list map of options for efficient navigation.
/// Port of OptionMap class from option-map.ts.
class OptionMapItem<T> {
  final Widget label;
  final T value;
  final String? description;
  OptionMapItem<T>? previous;
  OptionMapItem<T>? next;
  final int index;

  OptionMapItem({
    required this.label,
    required this.value,
    this.description,
    this.previous,
    this.next,
    required this.index,
  });
}

class OptionMap<T> {
  final Map<T, OptionMapItem<T>> _map = {};
  OptionMapItem<T>? first;
  OptionMapItem<T>? last;

  int get size => _map.length;

  OptionMap(List<SelectOption<T>> options) {
    OptionMapItem<T>? previous;
    int index = 0;

    for (final option in options) {
      final item = OptionMapItem<T>(
        label: option.label,
        value: option.value,
        description: option.description,
        previous: previous,
        index: index,
      );

      if (previous != null) {
        previous.next = item;
      }

      first ??= item;
      last = item;

      _map[option.value] = item;
      index++;
      previous = item;
    }
  }

  OptionMapItem<T>? get(T value) => _map[value];

  bool containsValue(T value) => _map.containsKey(value);
}

// ─── Select layout enum ──────────────────────────────────────────────────

enum SelectLayout { compact, expanded, compactVertical }

// ─── SelectController (port of useSelectState + useSelectNavigation) ─────

class SelectController<T> extends SintController {
  final List<SelectOption<T>> options;
  final T? defaultValue;
  final int visibleOptionCount;
  final ValueChanged<T>? onChange;
  final VoidCallback? onCancel;
  final ValueChanged<T>? onFocus;
  final T? defaultFocusValue;
  final VoidCallback? onUpFromFirstItem;
  final VoidCallback? onDownFromLastItem;

  SelectController({
    required this.options,
    this.defaultValue,
    this.visibleOptionCount = 5,
    this.onChange,
    this.onCancel,
    this.onFocus,
    this.defaultFocusValue,
    this.onUpFromFirstItem,
    this.onDownFromLastItem,
  });

  late final OptionMap<T> optionMap;

  final focusedValue = Rxn<T>();
  final selectedValue = Rxn<T>();
  final visibleFromIndex = 0.obs;
  final visibleToIndex = 0.obs;
  final isInInput = false.obs;

  // For input-type options
  final inputValues = <T, String>{}.obs;

  @override
  void onInit() {
    super.onInit();
    optionMap = OptionMap<T>(options);
    selectedValue.value = defaultValue;

    // Initialize focus
    if (defaultFocusValue != null &&
        optionMap.containsValue(defaultFocusValue as T)) {
      focusedValue.value = defaultFocusValue;
      _scrollToFocus();
    } else if (optionMap.first != null) {
      focusedValue.value = optionMap.first!.value;
    }

    final effectiveCount = math.min(visibleOptionCount, options.length);
    visibleToIndex.value = effectiveCount;

    // Initialize input values
    for (final opt in options) {
      if (opt.type == SelectOptionType.input && opt.initialValue != null) {
        inputValues[opt.value] = opt.initialValue!;
      }
    }
  }

  /// Focus next option and scroll down if needed.
  /// Port of focus-next-option action from use-select-navigation.ts reducer.
  void focusNextOption() {
    final current = focusedValue.value;
    if (current == null) return;

    final item = optionMap.get(current);
    if (item == null) return;

    // Wrap to first item if at the end
    final next = item.next ?? optionMap.first;
    if (next == null) return;

    // Check for onDownFromLastItem callback
    if (item.next == null && onDownFromLastItem != null) {
      onDownFromLastItem!();
      return;
    }

    // When wrapping to first, reset viewport
    if (item.next == null && next == optionMap.first) {
      focusedValue.value = next.value;
      visibleFromIndex.value = 0;
      visibleToIndex.value = math.min(visibleOptionCount, optionMap.size);
      onFocus?.call(next.value);
      return;
    }

    final needsScroll = next.index >= visibleToIndex.value;
    focusedValue.value = next.value;

    if (needsScroll) {
      final newTo = math.min(optionMap.size, visibleToIndex.value + 1);
      final newFrom = newTo - visibleOptionCount;
      visibleToIndex.value = newTo;
      visibleFromIndex.value = newFrom;
    }

    onFocus?.call(next.value);
  }

  /// Focus previous option and scroll up if needed.
  /// Port of focus-previous-option action from use-select-navigation.ts reducer.
  void focusPreviousOption() {
    final current = focusedValue.value;
    if (current == null) return;

    final item = optionMap.get(current);
    if (item == null) return;

    // Wrap to last item if at the beginning
    final previous = item.previous ?? optionMap.last;
    if (previous == null) return;

    // Check for onUpFromFirstItem callback
    if (item.previous == null && onUpFromFirstItem != null) {
      onUpFromFirstItem!();
      return;
    }

    // When wrapping to last, reset viewport to end
    if (item.previous == null && previous == optionMap.last) {
      final newTo = optionMap.size;
      final newFrom = math.max(0, newTo - visibleOptionCount);
      focusedValue.value = previous.value;
      visibleFromIndex.value = newFrom;
      visibleToIndex.value = newTo;
      onFocus?.call(previous.value);
      return;
    }

    final needsScroll = previous.index <= visibleFromIndex.value;
    focusedValue.value = previous.value;

    if (needsScroll) {
      final newFrom = math.max(0, visibleFromIndex.value - 1);
      final newTo = newFrom + visibleOptionCount;
      visibleFromIndex.value = newFrom;
      visibleToIndex.value = newTo;
    }

    onFocus?.call(previous.value);
  }

  /// Focus next page (jump by visibleOptionCount).
  /// Port of focus-next-page action from use-select-navigation.ts reducer.
  void focusNextPage() {
    final current = focusedValue.value;
    if (current == null) return;

    final item = optionMap.get(current);
    if (item == null) return;

    final targetIndex = math.min(
      optionMap.size - 1,
      item.index + visibleOptionCount,
    );

    // Walk to target index
    OptionMapItem<T>? target = optionMap.first;
    for (int i = 0; i < targetIndex && target != null; i++) {
      target = target.next;
    }
    if (target == null) return;

    focusedValue.value = target.value;
    _scrollToFocus();
    onFocus?.call(target.value);
  }

  /// Focus previous page.
  /// Port of focus-previous-page action from use-select-navigation.ts reducer.
  void focusPreviousPage() {
    final current = focusedValue.value;
    if (current == null) return;

    final item = optionMap.get(current);
    if (item == null) return;

    final targetIndex = math.max(0, item.index - visibleOptionCount);

    OptionMapItem<T>? target = optionMap.first;
    for (int i = 0; i < targetIndex && target != null; i++) {
      target = target.next;
    }
    if (target == null) return;

    focusedValue.value = target.value;
    _scrollToFocus();
    onFocus?.call(target.value);
  }

  /// Focus a specific option by value.
  void focusOption(T? value) {
    if (value == null) return;
    final item = optionMap.get(value);
    if (item == null) return;
    focusedValue.value = value;
    _scrollToFocus();
    onFocus?.call(value);
  }

  /// Select the currently focused option.
  void selectFocusedOption() {
    final focused = focusedValue.value;
    if (focused == null) return;

    // Check if the option is disabled
    final optIndex = options.indexWhere((o) => o.value == focused);
    if (optIndex >= 0 && options[optIndex].disabled) return;

    selectedValue.value = focused;
    onChange?.call(focused);
  }

  /// Get the visible options for rendering.
  // ignore: library_private_types_in_public_api
  List<_VisibleOption<T>> get visibleOptions {
    final from = visibleFromIndex.value;
    final to = math.min(visibleToIndex.value, options.length);
    final result = <_VisibleOption<T>>[];

    for (int i = from; i < to; i++) {
      result.add(
        _VisibleOption(
          option: options[i],
          index: i,
          isFocused: options[i].value == focusedValue.value,
          isSelected: options[i].value == selectedValue.value,
        ),
      );
    }
    return result;
  }

  bool get showUpArrow => visibleFromIndex.value > 0;
  bool get showDownArrow => visibleToIndex.value < options.length;

  void _scrollToFocus() {
    final current = focusedValue.value;
    if (current == null) return;
    final item = optionMap.get(current);
    if (item == null) return;

    if (item.index < visibleFromIndex.value) {
      visibleFromIndex.value = item.index;
      visibleToIndex.value = item.index + visibleOptionCount;
    } else if (item.index >= visibleToIndex.value) {
      visibleToIndex.value = item.index + 1;
      visibleFromIndex.value = math.max(
        0,
        visibleToIndex.value - visibleOptionCount,
      );
    }
  }

  /// Update an input option's value.
  void updateInputValue(T optionValue, String text) {
    inputValues[optionValue] = text;
    final opt = options.firstWhere((o) => o.value == optionValue);
    opt.onInputChange?.call(text);
  }
}

// ─── Visible option helper ───────────────────────────────────────────────

class _VisibleOption<T> {
  final SelectOption<T> option;
  final int index;
  final bool isFocused;
  final bool isSelected;

  const _VisibleOption({
    required this.option,
    required this.index,
    required this.isFocused,
    required this.isSelected,
  });
}

// ─── CustomSelect widget (port of Select from select.tsx) ────────────────

class CustomSelect<T> extends StatelessWidget {
  final List<SelectOption<T>> options;
  final T? defaultValue;
  final int visibleOptionCount;
  final ValueChanged<T>? onChange;
  final VoidCallback? onCancel;
  final ValueChanged<T>? onFocus;
  final T? defaultFocusValue;
  final SelectLayout layout;
  final bool hideIndexes;
  final bool isDisabled;
  final bool disableSelection;
  final String? highlightText;
  final bool inlineDescriptions;
  final VoidCallback? onUpFromFirstItem;
  final VoidCallback? onDownFromLastItem;
  final String? tag;

  const CustomSelect({
    super.key,
    required this.options,
    this.defaultValue,
    this.visibleOptionCount = 5,
    this.onChange,
    this.onCancel,
    this.onFocus,
    this.defaultFocusValue,
    this.layout = SelectLayout.compact,
    this.hideIndexes = false,
    this.isDisabled = false,
    this.disableSelection = false,
    this.highlightText,
    this.inlineDescriptions = false,
    this.onUpFromFirstItem,
    this.onDownFromLastItem,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final controllerTag = tag ?? 'select_${identityHashCode(this)}';
    final controller = Sint.put(
      SelectController<T>(
        options: options,
        defaultValue: defaultValue,
        visibleOptionCount: visibleOptionCount,
        onChange: onChange,
        onCancel: onCancel,
        onFocus: onFocus,
        defaultFocusValue: defaultFocusValue,
        onUpFromFirstItem: onUpFromFirstItem,
        onDownFromLastItem: onDownFromLastItem,
      ),
      tag: controllerTag,
    );

    return Focus(
      autofocus: true,
      onKeyEvent: isDisabled
          ? null
          : (node, event) => _handleKeyEvent(event, controller),
      child: Obx(() {
        final visible = controller.visibleOptions;
        final showUp = controller.showUpArrow;
        final showDown = controller.showDownArrow;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Scroll up indicator ──
            if (showUp)
              Padding(
                padding: const EdgeInsets.only(left: 16, bottom: 2),
                child: Icon(
                  Icons.keyboard_arrow_up,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),

            // ── Options ──
            ...visible.asMap().entries.map((entry) {
              final idx = entry.key;
              final vo = entry.value;

              return _SelectOptionTile<T>(
                option: vo.option,
                index: vo.index,
                isFocused: vo.isFocused,
                isSelected: vo.isSelected,
                hideIndex: hideIndexes,
                layout: layout,
                highlightText: highlightText,
                inlineDescriptions: inlineDescriptions,
                showUpArrow: idx == 0 && showUp,
                showDownArrow: idx == visible.length - 1 && showDown,
                inputValue: controller.inputValues[vo.option.value],
                onTap: isDisabled || disableSelection
                    ? null
                    : () {
                        controller.focusOption(vo.option.value);
                        controller.selectFocusedOption();
                      },
                onInputChanged: vo.option.type == SelectOptionType.input
                    ? (text) =>
                          controller.updateInputValue(vo.option.value, text)
                    : null,
              );
            }),

            // ── Scroll down indicator ──
            if (showDown)
              Padding(
                padding: const EdgeInsets.only(left: 16, top: 2),
                child: Icon(
                  Icons.keyboard_arrow_down,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        );
      }),
    );
  }

  KeyEventResult _handleKeyEvent(
    KeyEvent event,
    SelectController<T> controller,
  ) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    final key = event.logicalKey;

    if (key == LogicalKeyboardKey.arrowUp) {
      controller.focusPreviousOption();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      controller.focusNextOption();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      controller.focusPreviousPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageDown) {
      controller.focusNextPage();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter) {
      if (!disableSelection) {
        controller.selectFocusedOption();
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      onCancel?.call();
      return KeyEventResult.handled;
    }

    // Number key shortcuts (1-9) for quick select
    if (!hideIndexes) {
      final numKey = _logicalKeyToNumber(key);
      if (numKey != null && numKey >= 1 && numKey <= options.length) {
        controller.focusOption(options[numKey - 1].value);
        if (!disableSelection) {
          controller.selectFocusedOption();
        }
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  int? _logicalKeyToNumber(LogicalKeyboardKey key) {
    final mapping = {
      LogicalKeyboardKey.digit1: 1,
      LogicalKeyboardKey.digit2: 2,
      LogicalKeyboardKey.digit3: 3,
      LogicalKeyboardKey.digit4: 4,
      LogicalKeyboardKey.digit5: 5,
      LogicalKeyboardKey.digit6: 6,
      LogicalKeyboardKey.digit7: 7,
      LogicalKeyboardKey.digit8: 8,
      LogicalKeyboardKey.digit9: 9,
    };
    return mapping[key];
  }
}

// ─── SelectOptionTile widget (port of SelectOption from select-option.tsx) ──

class _SelectOptionTile<T> extends StatelessWidget {
  final SelectOption<T> option;
  final int index;
  final bool isFocused;
  final bool isSelected;
  final bool hideIndex;
  final SelectLayout layout;
  final String? highlightText;
  final bool inlineDescriptions;
  final bool showUpArrow;
  final bool showDownArrow;
  final String? inputValue;
  final VoidCallback? onTap;
  final ValueChanged<String>? onInputChanged;

  const _SelectOptionTile({
    required this.option,
    required this.index,
    required this.isFocused,
    required this.isSelected,
    this.hideIndex = false,
    this.layout = SelectLayout.compact,
    this.highlightText,
    this.inlineDescriptions = false,
    this.showUpArrow = false,
    this.showDownArrow = false,
    this.inputValue,
    this.onTap,
    this.onInputChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isExpanded = layout == SelectLayout.expanded;
    final isCompactVertical = layout == SelectLayout.compactVertical;

    return InkWell(
      onTap: option.disabled ? null : onTap,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: 12,
          vertical: isExpanded ? 8 : 4,
        ),
        decoration: BoxDecoration(
          color: isFocused
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : null,
          border: isFocused
              ? Border(
                  left: BorderSide(color: theme.colorScheme.primary, width: 2),
                )
              : null,
        ),
        child: Row(
          children: [
            // ── Index number ──
            if (!hideIndex)
              SizedBox(
                width: 24,
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    color: isFocused
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 13,
                    fontWeight: isFocused ? FontWeight.bold : null,
                  ),
                ),
              ),

            // ── Focus indicator ──
            Text(
              isFocused ? '\u276F ' : '  ',
              style: TextStyle(color: theme.colorScheme.primary, fontSize: 13),
            ),

            // ── Label + description ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Label row
                  Row(
                    children: [
                      Flexible(child: option.label),

                      // Inline description
                      if (inlineDescriptions &&
                          option.description != null &&
                          !isCompactVertical)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(
                            option.description!,
                            style: TextStyle(
                              color: option.dimDescription
                                  ? theme.colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.5)
                                  : theme.colorScheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                  ),

                  // Vertical description (compact-vertical or expanded)
                  if ((isCompactVertical || isExpanded) &&
                      option.description != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        option.description!,
                        style: TextStyle(
                          color: option.dimDescription
                              ? theme.colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                )
                              : theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                        maxLines: isExpanded ? 3 : 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),

                  // Input field for input-type options
                  if (option.type == SelectOptionType.input && isFocused)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: TextField(
                        autofocus: true,
                        controller: TextEditingController(
                          text: inputValue ?? option.initialValue ?? '',
                        ),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          hintText: option.placeholder ?? 'Type here...',
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        onChanged: onInputChanged,
                      ),
                    ),
                ],
              ),
            ),

            // ── Disabled indicator ──
            if (option.disabled)
              Padding(
                padding: const EdgeInsets.only(left: 4),
                child: Text(
                  'disabled',
                  style: TextStyle(
                    color: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.5,
                    ),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── MultiSelect widget (port of SelectMulti.tsx) ────────────────────────

class MultiSelectController<T> extends SintController {
  final List<SelectOption<T>> options;
  final Set<T> initialSelected;
  final ValueChanged<Set<T>>? onChange;
  final VoidCallback? onCancel;

  MultiSelectController({
    required this.options,
    this.initialSelected = const {},
    this.onChange,
    this.onCancel,
  });

  final selectedValues = <T>{}.obs;
  final focusedIndex = 0.obs;

  @override
  void onInit() {
    super.onInit();
    selectedValues.addAll(initialSelected);
  }

  void toggleOption(T value) {
    if (selectedValues.contains(value)) {
      selectedValues.remove(value);
    } else {
      selectedValues.add(value);
    }
    onChange?.call(selectedValues.toSet());
  }

  void focusNext() {
    if (focusedIndex.value < options.length - 1) {
      focusedIndex.value++;
    }
  }

  void focusPrevious() {
    if (focusedIndex.value > 0) {
      focusedIndex.value--;
    }
  }

  void toggleFocused() {
    if (options.isNotEmpty) {
      toggleOption(options[focusedIndex.value].value);
    }
  }
}

class CustomMultiSelect<T> extends StatelessWidget {
  final List<SelectOption<T>> options;
  final Set<T> initialSelected;
  final ValueChanged<Set<T>>? onChange;
  final VoidCallback? onCancel;
  final VoidCallback? onConfirm;
  final String? tag;

  const CustomMultiSelect({
    super.key,
    required this.options,
    this.initialSelected = const {},
    this.onChange,
    this.onCancel,
    this.onConfirm,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    final controllerTag = tag ?? 'multi_select_${identityHashCode(this)}';
    final controller = Sint.put(
      MultiSelectController<T>(
        options: options,
        initialSelected: initialSelected,
        onChange: onChange,
        onCancel: onCancel,
      ),
      tag: controllerTag,
    );

    final theme = Theme.of(context);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowUp) {
          controller.focusPrevious();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowDown) {
          controller.focusNext();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.space) {
          controller.toggleFocused();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.enter) {
          onConfirm?.call();
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          onCancel?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Obx(() {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: options.asMap().entries.map((entry) {
            final idx = entry.key;
            final opt = entry.value;
            final focused = idx == controller.focusedIndex.value;
            final selected = controller.selectedValues.contains(opt.value);

            return InkWell(
              onTap: opt.disabled
                  ? null
                  : () => controller.toggleOption(opt.value),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: focused
                      ? theme.colorScheme.primary.withValues(alpha: 0.08)
                      : null,
                ),
                child: Row(
                  children: [
                    // Checkbox
                    Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 18,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    // Label
                    Expanded(child: opt.label),
                    // Description
                    if (opt.description != null)
                      Text(
                        opt.description!,
                        style: TextStyle(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            );
          }).toList(),
        );
      }),
    );
  }
}
