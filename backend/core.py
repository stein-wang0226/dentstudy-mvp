"""DentStudy deterministic event reducer; business calendar is Asia/Shanghai."""
from datetime import datetime, timedelta, timezone

TZ = timezone(timedelta(hours=8))
INTERVALS = [1, 2, 4, 7, 14]


def business_day(timestamp):
    return datetime.fromisoformat(timestamp.replace('Z', '+00:00')).astimezone(TZ).date()


def today():
    return datetime.now(TZ).date()


def reduce_events(events, questions):
    states, attempts = {}, []
    bank = {q['id']: q for q in questions}
    for event in sorted(events, key=lambda e: (datetime.fromisoformat(e['at'].replace('Z', '+00:00')), e['id'])):
        qid = event['questionId']
        state = states.setdefault(qid, dict(stage=-1, due=None, lastDay=None,
            wrong=False, favorite=False, note='', grade=None))
        kind, value = event['kind'], event.get('value')
        if kind in ('favorite', 'note'):
            state[kind] = value
        elif kind == 'removeWrong':
            state['wrong'] = False  # Does not cancel an existing review schedule.
        elif kind == 'review':
            q = bank[qid]
            correct = value.get('answer') == q['answer'] if q['answer'] else None
            grade = 'wrong' if correct is False else value['grade']
            day = business_day(event['at'])
            if grade == 'wrong':
                state['stage'] = 0
                state['wrong'] = True
            elif grade == 'guessed':
                state['stage'] = max(0, state['stage'] - 1)
            elif state['lastDay'] != day.isoformat():
                # Early voluntary attempts never advance a future review.
                if state['due'] is None or day.isoformat() >= state['due']:
                    state['stage'] = min(4, state['stage'] + 1)
            state['stage'] = max(0, state['stage'])
            due = (day + timedelta(days=INTERVALS[state['stage']])).isoformat()
            if grade != 'mastered' or state['lastDay'] != day.isoformat():
                if grade != 'mastered' or not state['due'] or state['due'] <= day.isoformat():
                    state['due'] = due
            if state['due'] is None:
                state['due'] = due
            state['lastDay'], state['grade'] = day.isoformat(), grade
            attempts.append(dict(id=event['id'], questionId=qid, at=event['at'],
                                 correct=correct, grade=grade, mode=value.get('mode', 'practice')))
    return states, attempts


def plan(states, questions, day=None):
    day = (day or today()).isoformat()
    due = [q['id'] for q in questions if states.get(q['id'], {}).get('due')
           and states[q['id']]['due'] <= day]
    due.sort(key=lambda qid: (states[qid]['grade'] != 'wrong', states[qid]['due'], qid))
    new = [q['id'] for q in questions if not states.get(q['id'], {}).get('lastDay')]
    return dict(day=day, due=due, new=new if not due else [], newLocked=bool(due))
