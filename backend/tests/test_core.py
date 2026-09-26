import unittest
from datetime import date
from core import reduce_events, plan, business_day

QUESTIONS=[{'id':'q1','answer':'A'}, {'id':'q2','answer':None}]

def event(n,day,grade='mastered',answer='A',qid='q1',kind='review',value=None):
    return dict(id=f'event-{n:020}',at=f'{day}T04:00:00.000000Z',questionId=qid,kind=kind,
        value=dict(grade=grade,answer=answer) if kind=='review' else value)

class SchedulingTests(unittest.TestCase):
    def test_intervals(self):
        dates=['2026-01-01','2026-01-02','2026-01-04','2026-01-08','2026-01-15','2026-01-29']
        expected=['2026-01-02','2026-01-04','2026-01-08','2026-01-15','2026-01-29','2026-02-12']
        history=[]
        for i,day in enumerate(dates):
            history.append(event(i,day))
            states,_=reduce_events(history,QUESTIONS)
            self.assertEqual(states['q1']['due'],expected[i])

    def test_wrong_answer_overrides_claimed_mastery(self):
        states,attempts=reduce_events([event(1,'2026-01-01',answer='B')],QUESTIONS)
        self.assertEqual(states['q1']['grade'],'wrong')
        self.assertEqual(states['q1']['due'],'2026-01-02')
        self.assertFalse(attempts[0]['correct'])

    def test_same_day_does_not_jump(self):
        states,_=reduce_events([event(i,'2026-01-01') for i in range(6)],QUESTIONS)
        self.assertEqual(states['q1']['stage'],0)
        self.assertEqual(states['q1']['due'],'2026-01-02')

    def test_wrong_then_correct_same_day_stays_one_day(self):
        states,_=reduce_events([event(1,'2026-01-01','wrong'),event(2,'2026-01-01')],QUESTIONS)
        self.assertEqual(states['q1']['due'],'2026-01-02')
        self.assertTrue(states['q1']['wrong'])

    def test_early_mastery_does_not_postpone_due(self):
        states,_=reduce_events([event(1,'2026-01-01'),event(2,'2026-01-02'),event(3,'2026-01-03')],QUESTIONS)
        self.assertEqual(states['q1']['due'],'2026-01-04')
        self.assertEqual(states['q1']['stage'],1)

    def test_guess_shortens_interval(self):
        states,_=reduce_events([event(1,'2026-01-01'),event(2,'2026-01-02'),event(3,'2026-01-04'),event(4,'2026-01-08','guessed')],QUESTIONS)
        self.assertEqual(states['q1']['stage'],1)
        self.assertEqual(states['q1']['due'],'2026-01-10')

    def test_subjective_never_auto_scores(self):
        _,attempts=reduce_events([event(1,'2026-01-01',qid='q2',answer='我的分析')],QUESTIONS)
        self.assertIsNone(attempts[0]['correct'])

    def test_review_first_lock_and_release(self):
        states,_=reduce_events([event(1,'2026-01-01','wrong')],QUESTIONS)
        p=plan(states,QUESTIONS,date(2026,1,2))
        self.assertTrue(p['newLocked']); self.assertEqual(p['new'],[])
        states,_=reduce_events([event(1,'2026-01-01','wrong'),event(2,'2026-01-02')],QUESTIONS)
        p=plan(states,QUESTIONS,date(2026,1,2))
        self.assertFalse(p['newLocked']);self.assertEqual(p['new'],['q2'])

    def test_out_of_order_sync_and_note_conflicts(self):
        a=event(1,'2026-01-01',kind='note',value='old')
        b=event(2,'2026-01-02',kind='note',value='new')
        self.assertEqual(reduce_events([b,a],QUESTIONS)[0]['q1']['note'],'new')

    def test_wrong_removal_does_not_delete_schedule(self):
        states,_=reduce_events([event(1,'2026-01-01','wrong'),event(2,'2026-01-02',kind='removeWrong')],QUESTIONS)
        self.assertFalse(states['q1']['wrong']);self.assertEqual(states['q1']['due'],'2026-01-02')

    def test_business_timezone(self):
        self.assertEqual(business_day('2026-01-01T16:00:00Z'),date(2026,1,2))

if __name__=='__main__':unittest.main()
