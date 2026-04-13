import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:neomage/utils/teammate/teammate_utils.dart';

void main() {
  // Make sure module-level dynamic context is reset between tests so they
  // remain independent.
  setUp(() {
    clearDynamicTeamContext();
  });
  tearDown(() {
    clearDynamicTeamContext();
  });

  group('Dynamic team context', () {
    test('initially null and isTeammate=false', () {
      expect(getDynamicTeamContext(), isNull);
      expect(isTeammate(), isFalse);
      expect(getAgentId(), isNull);
      expect(getAgentName(), isNull);
      expect(getTeammateColor(), isNull);
    });

    test('set / clear works', () {
      setDynamicTeamContext(
        DynamicTeamContext(
          agentId: 'researcher@team-a',
          agentName: 'researcher',
          teamName: 'team-a',
          color: 'blue',
          planModeRequired: true,
          parentSessionId: 'sess-1',
        ),
      );
      expect(isTeammate(), isTrue);
      expect(getAgentId(), 'researcher@team-a');
      expect(getAgentName(), 'researcher');
      expect(getTeamName(), 'team-a');
      expect(getTeammateColor(), 'blue');
      expect(isPlanModeRequired(), isTrue);
      expect(getParentSessionId(), 'sess-1');

      clearDynamicTeamContext();
      expect(getDynamicTeamContext(), isNull);
      expect(isTeammate(), isFalse);
    });

    test('isTeammate is false when teamName is empty', () {
      setDynamicTeamContext(
        DynamicTeamContext(
          agentId: 'a',
          agentName: 'a',
          teamName: '',
          planModeRequired: false,
        ),
      );
      expect(isTeammate(), isFalse);
    });

    test('isTeammate is false when agentId is empty', () {
      setDynamicTeamContext(
        DynamicTeamContext(
          agentId: '',
          agentName: 'a',
          teamName: 't',
          planModeRequired: false,
        ),
      );
      expect(isTeammate(), isFalse);
    });

    test('getTeamName falls back to teamContextTeamName when no dynamic ctx', () {
      expect(
        getTeamName(teamContextTeamName: 'fallback'),
        'fallback',
      );
    });
  });

  group('runWithTeammateContext (in-process zone-based)', () {
    test('outside zone, getTeammateContext is null', () {
      expect(getTeammateContext(), isNull);
      expect(isInProcessTeammate(), isFalse);
    });

    test('inside zone, the context is visible', () {
      final ctx = createTeammateContext(
        agentId: 'a@t',
        agentName: 'a',
        teamName: 't',
        planModeRequired: false,
        parentSessionId: 'p',
      );

      runWithTeammateContext(ctx, () {
        expect(getTeammateContext(), same(ctx));
        expect(isInProcessTeammate(), isTrue);
        expect(getAgentId(), 'a@t');
        expect(getAgentName(), 'a');
        expect(getTeamName(), 't');
        expect(isTeammate(), isTrue);
      });

      // and is restored on exit
      expect(getTeammateContext(), isNull);
    });

    test('in-process context overrides dynamic context', () {
      setDynamicTeamContext(
        DynamicTeamContext(
          agentId: 'dyn@t',
          agentName: 'dyn',
          teamName: 't',
          planModeRequired: false,
        ),
      );
      final ctx = createTeammateContext(
        agentId: 'inproc@t',
        agentName: 'inproc',
        teamName: 't',
        planModeRequired: true,
        parentSessionId: 'p',
      );
      runWithTeammateContext(ctx, () {
        expect(getAgentId(), 'inproc@t');
        expect(isPlanModeRequired(), isTrue);
      });
      // Outside the zone, dynamic ctx visible again
      expect(getAgentId(), 'dyn@t');
    });
  });

  group('isTeamLead', () {
    test('false when leadAgentId is null or empty', () {
      expect(isTeamLead(leadAgentId: null), isFalse);
      expect(isTeamLead(leadAgentId: ''), isFalse);
    });

    test('true when no agent ID set (legacy path)', () {
      expect(isTeamLead(leadAgentId: 'leader@t'), isTrue);
    });

    test('true when my agent ID equals leadAgentId', () {
      setDynamicTeamContext(
        DynamicTeamContext(
          agentId: 'leader@t',
          agentName: 'l',
          teamName: 't',
          planModeRequired: false,
        ),
      );
      expect(isTeamLead(leadAgentId: 'leader@t'), isTrue);
    });

    test('false when my agent ID differs from leadAgentId', () {
      setDynamicTeamContext(
        DynamicTeamContext(
          agentId: 'worker@t',
          agentName: 'w',
          teamName: 't',
          planModeRequired: false,
        ),
      );
      expect(isTeamLead(leadAgentId: 'leader@t'), isFalse);
    });
  });

  group('hasActive / hasWorking InProcessTeammates', () {
    test('empty -> false', () {
      expect(hasActiveInProcessTeammates({}), isFalse);
      expect(hasWorkingInProcessTeammates({}), isFalse);
    });

    test('non-teammate task ignored', () {
      final tasks = {
        'a': InProcessTeammateTask(type: 'other', status: 'running'),
      };
      expect(hasActiveInProcessTeammates(tasks), isFalse);
      expect(hasWorkingInProcessTeammates(tasks), isFalse);
    });

    test('idle teammate is "active" but not "working"', () {
      final tasks = {
        'a': InProcessTeammateTask(
          type: 'in_process_teammate',
          status: 'running',
          isIdle: true,
        ),
      };
      expect(hasActiveInProcessTeammates(tasks), isTrue);
      expect(hasWorkingInProcessTeammates(tasks), isFalse);
    });

    test('busy teammate is both active and working', () {
      final tasks = {
        'a': InProcessTeammateTask(
          type: 'in_process_teammate',
          status: 'running',
          isIdle: false,
        ),
      };
      expect(hasActiveInProcessTeammates(tasks), isTrue);
      expect(hasWorkingInProcessTeammates(tasks), isTrue);
    });

    test('non-running teammate is neither', () {
      final tasks = {
        'a': InProcessTeammateTask(
          type: 'in_process_teammate',
          status: 'completed',
        ),
      };
      expect(hasActiveInProcessTeammates(tasks), isFalse);
      expect(hasWorkingInProcessTeammates(tasks), isFalse);
    });
  });

  group('formatTeammateMessages', () {
    test('empty list -> empty string', () {
      expect(formatTeammateMessages([]), '');
    });

    test('renders <teammate_message> wrapping each message', () {
      final out = formatTeammateMessages([
        TeammateMessage(
          from: 'alice',
          text: 'hello',
          timestamp: 't1',
          read: false,
        ),
      ]);
      expect(out, contains('<teammate_message teammate_id="alice"'));
      expect(out, contains('hello'));
      expect(out, contains('</teammate_message>'));
    });

    test('color and summary attributes only when present', () {
      final withAttrs = formatTeammateMessages([
        TeammateMessage(
          from: 'a',
          text: 't',
          timestamp: 't',
          read: false,
          color: 'red',
          summary: 'sum',
        ),
      ]);
      expect(withAttrs, contains('color="red"'));
      expect(withAttrs, contains('summary="sum"'));

      final without = formatTeammateMessages([
        TeammateMessage(from: 'a', text: 't', timestamp: 't', read: false),
      ]);
      expect(without, isNot(contains('color=')));
      expect(without, isNot(contains('summary=')));
    });

    test('multiple messages joined with double newline', () {
      final out = formatTeammateMessages([
        TeammateMessage(from: 'a', text: '1', timestamp: 't', read: false),
        TeammateMessage(from: 'b', text: '2', timestamp: 't', read: false),
      ]);
      expect(out.split('\n\n').length, 2);
    });
  });

  group('TeammateMessage JSON', () {
    test('round trip with optional fields', () {
      final m = TeammateMessage(
        from: 'a',
        text: 't',
        timestamp: 'ts',
        read: true,
        color: 'c',
        summary: 's',
      );
      final back = TeammateMessage.fromJson(m.toJson());
      expect(back.from, 'a');
      expect(back.text, 't');
      expect(back.read, isTrue);
      expect(back.color, 'c');
      expect(back.summary, 's');
    });

    test('toJson omits null color/summary', () {
      final j =
          TeammateMessage(from: 'a', text: 't', timestamp: 'ts', read: false)
              .toJson();
      expect(j.containsKey('color'), isFalse);
      expect(j.containsKey('summary'), isFalse);
    });

    test('copyWith only mutates read flag', () {
      final m = TeammateMessage(from: 'a', text: 't', timestamp: 'ts', read: false);
      final c = m.copyWith(read: true);
      expect(c.read, isTrue);
      expect(c.from, 'a');
      expect(c.text, 't');
    });

    test('fromJson defaults missing fields safely', () {
      final m = TeammateMessage.fromJson({});
      expect(m.from, '');
      expect(m.text, '');
      expect(m.timestamp, '');
      expect(m.read, isFalse);
      expect(m.color, isNull);
    });
  });

  group('IdleNotificationMessage / isIdleNotification', () {
    test('createIdleNotification fills agent id and timestamp', () {
      final n = createIdleNotification('worker@t', idleReason: 'available');
      expect(n.from, 'worker@t');
      expect(n.idleReason, 'available');
      expect(n.timestamp, isNotEmpty);
    });

    test('toJson round trip', () {
      final n = createIdleNotification(
        'a',
        idleReason: 'failed',
        summary: 's',
        completedTaskId: 't',
        completedStatus: 'failed',
        failureReason: 'oops',
      );
      final json = n.toJson();
      final back = IdleNotificationMessage.fromJson(json);
      expect(back.from, 'a');
      expect(back.idleReason, 'failed');
      expect(back.summary, 's');
      expect(back.completedTaskId, 't');
      expect(back.completedStatus, 'failed');
      expect(back.failureReason, 'oops');
      expect(json['type'], 'idle_notification');
    });

    test('isIdleNotification: valid JSON returns parsed message', () {
      final n = createIdleNotification('a');
      final text = jsonEncode(n.toJson());
      final parsed = isIdleNotification(text);
      expect(parsed, isNotNull);
      expect(parsed!.from, 'a');
    });

    test('isIdleNotification: wrong type -> null', () {
      final text = jsonEncode({'type': 'something_else', 'from': 'a'});
      expect(isIdleNotification(text), isNull);
    });

    test('isIdleNotification: malformed JSON -> null (no throw)', () {
      expect(isIdleNotification('not json'), isNull);
      expect(isIdleNotification(''), isNull);
      expect(isIdleNotification('[]'), isNull);
    });
  });

  group('createPermissionRequestMessage / isPermissionRequest', () {
    test('round trip', () {
      final req = createPermissionRequestMessage(
        requestId: 'r1',
        agentId: 'a',
        toolName: 'Bash',
        toolUseId: 'u',
        description: 'd',
        input: {'cmd': 'ls'},
        permissionSuggestions: ['allow'],
      );
      final text = jsonEncode(req.toJson());
      final parsed = isPermissionRequest(text);
      expect(parsed, isNotNull);
      expect(parsed!.requestId, 'r1');
      expect(parsed.agentId, 'a');
      expect(parsed.toolName, 'Bash');
      expect(parsed.input, {'cmd': 'ls'});
      expect(parsed.permissionSuggestions, ['allow']);
    });

    test('wrong type -> null', () {
      expect(
        isPermissionRequest(jsonEncode({'type': 'permission_response'})),
        isNull,
      );
    });

    test('malformed -> null', () {
      expect(isPermissionRequest('garbage'), isNull);
      expect(isPermissionRequest(''), isNull);
    });

    test('default permissionSuggestions is empty when omitted', () {
      final req = createPermissionRequestMessage(
        requestId: 'r',
        agentId: 'a',
        toolName: 't',
        toolUseId: 'u',
        description: 'd',
        input: {},
      );
      expect(req.permissionSuggestions, isEmpty);
    });
  });

  group('createPermissionResponseMessage / isPermissionResponse', () {
    test('subtype=success returns Success and round-trips', () {
      final resp = createPermissionResponseMessage(
        requestId: 'r',
        subtype: 'success',
        updatedInput: {'cmd': 'ls'},
        permissionUpdates: ['allow'],
      );
      expect(resp, isA<PermissionResponseSuccess>());
      final json = (resp as PermissionResponseSuccess).toJson();
      final back = isPermissionResponse(jsonEncode(json));
      expect(back, isA<PermissionResponseSuccess>());
      final s = back as PermissionResponseSuccess;
      expect(s.requestId, 'r');
      expect(s.updatedInput, {'cmd': 'ls'});
      expect(s.permissionUpdates, ['allow']);
    });

    test('subtype=error returns Error and round-trips', () {
      final resp = createPermissionResponseMessage(
        requestId: 'r',
        subtype: 'error',
        error: 'denied',
      );
      expect(resp, isA<PermissionResponseError>());
      final json = (resp as PermissionResponseError).toJson();
      final back = isPermissionResponse(jsonEncode(json));
      expect(back, isA<PermissionResponseError>());
      expect((back as PermissionResponseError).error, 'denied');
    });

    test('error without explicit message uses default', () {
      final resp = createPermissionResponseMessage(
        requestId: 'r',
        subtype: 'error',
      );
      expect((resp as PermissionResponseError).error, 'Permission denied');
    });

    test('isPermissionResponse: malformed -> null', () {
      expect(isPermissionResponse('garbage'), isNull);
      expect(isPermissionResponse(''), isNull);
    });

    test('isPermissionResponse: wrong type -> null', () {
      expect(
        isPermissionResponse(jsonEncode({'type': 'idle_notification'})),
        isNull,
      );
    });
  });
}
