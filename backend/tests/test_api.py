import copy
import json
import tempfile
import threading
import unittest
import urllib.request
import urllib.error
from pathlib import Path
from http.server import ThreadingHTTPServer
import server
from bank import validate

class ApiTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp=tempfile.TemporaryDirectory()
        server.DB=Path(cls.temp.name)/'test.sqlite'
        server.initialize()
        cls.http=ThreadingHTTPServer(('127.0.0.1',0),server.Handler)
        cls.thread=threading.Thread(target=cls.http.serve_forever,daemon=True)
        cls.thread.start()
        cls.url=f'http://127.0.0.1:{cls.http.server_port}'

    @classmethod
    def tearDownClass(cls):
        cls.http.shutdown();cls.http.server_close();cls.thread.join();cls.temp.cleanup()

    def request(self,path,data=None,token=None):
        headers={'Content-Type':'application/json'}
        if token:headers['Authorization']='Bearer '+token
        req=urllib.request.Request(self.url+path,data=json.dumps(data).encode() if data is not None else None,headers=headers)
        try:
            with urllib.request.urlopen(req) as r:return r.status,json.loads(r.read())
        except urllib.error.HTTPError as e:return e.code,json.loads(e.read())

    def register(self,name):
        status,result=self.request('/v1/auth/register',{'email':name+'@test.local','password':'testing-pass-123'})
        self.assertEqual(status,200)
        return result['token']

    def test_full_offline_retry_and_account_isolation(self):
        token=self.register('alice')
        event=dict(id='unique-event-1234567890',at='2026-01-01T04:00:00Z',questionId='demo-001',kind='review',value={'answer':'A','grade':'mastered'})
        for _ in range(2):
            status,data=self.request('/v1/sync',{'events':[event]},token)
            self.assertEqual(status,200)
            self.assertEqual(len(data['attempts']),1)
            self.assertEqual(data['attempts'][0]['grade'],'wrong')
        other=self.register('bob')
        self.assertEqual(self.request('/v1/state',token=other)[1]['events'],[])
        self.assertEqual(self.request('/v1/state')[0],401)
        self.assertEqual(self.request('/v1/auth/logout',{},token)[0],200)
        self.assertEqual(self.request('/v1/state',token=token)[0],401)

    def test_conflicting_id_is_rejected(self):
        token=self.register('conflict')
        e=dict(id='unique-note-1234567890',at='2026-01-01T04:00:00Z',questionId='demo-001',kind='note',value='First')
        self.assertEqual(self.request('/v1/sync',{'events':[e]},token)[0],200)
        e['value']='Changed'
        self.assertEqual(self.request('/v1/sync',{'events':[e]},token)[0],400)

    def test_atomic_invalid_batch_and_future_time(self):
        token=self.register('atomic')
        valid=dict(id='valid-note-1234567890',at='2026-01-01T04:00:00Z',questionId='demo-001',kind='note',value='Kept?')
        invalid={**valid,'id':'invalid-note-1234567890','at':'2999-01-01T00:00:00Z'}
        self.assertEqual(self.request('/v1/sync',{'events':[valid,invalid]},token)[0],400)
        self.assertEqual(self.request('/v1/state',token=token)[1]['events'],[])

    def test_login(self):
        self.register('login')
        self.assertEqual(self.request('/v1/auth/login',{'email':'login@test.local','password':'testing-pass-123'})[0],200)
        self.assertEqual(self.request('/v1/auth/login',{'email':'login@test.local','password':'incorrect-123'})[0],401)

    def test_question_download(self):
        status,bank=self.request('/v1/questions')
        self.assertEqual(status,200)
        self.assertEqual(bank, json.loads(server.BANK.read_text()))
        self.assertGreater(len(bank['questions']),0)
        self.assertEqual(validate(bank),[])
        self.assertTrue(validate(bank,production=True))

    def test_settings_sync_validation_and_account_isolation(self):
        token=self.register('settings')
        settings={'dailyNewLimit':25,'dailyReviewTarget':None,
                  'updatedAt':'2026-01-01T04:00:00Z'}
        status,data=self.request('/v1/sync',{'events':[],'settings':settings},token)
        self.assertEqual(status,200)
        self.assertEqual(data['settings']['dailyNewLimit'],25)
        self.assertIsNone(data['settings']['dailyReviewTarget'])
        stale={**settings,'dailyNewLimit':5,'updatedAt':'2025-01-01T04:00:00Z'}
        self.assertEqual(self.request('/v1/sync',{'events':[],'settings':stale},token)[1]['settings']['dailyNewLimit'],25)
        invalid={**settings,'dailyReviewTarget':201}
        self.assertEqual(self.request('/v1/sync',{'events':[],'settings':invalid},token)[0],400)
        expanded={**settings,'dailyNewLimit':1000000,'updatedAt':'2026-01-02T04:00:00Z'}
        self.assertEqual(self.request('/v1/sync',{'events':[],'settings':expanded},token)[1]['settings']['dailyNewLimit'],1000000)
        too_large={**expanded,'dailyNewLimit':1000001}
        self.assertEqual(self.request('/v1/sync',{'events':[],'settings':too_large},token)[0],400)
        other=self.register('settings-other')
        self.assertIsNone(self.request('/v1/state',token=other)[1]['settings'])

    def test_speed_modes_sync(self):
        token=self.register('speed-modes')
        events=[]
        for index,mode in enumerate(('speed','speed-review')):
            events.append(dict(
                id=f'speed-event-{index:020d}',
                at=f'2026-01-0{index + 1}T04:00:00Z',
                questionId='demo-001',kind='review',
                value={'answer':'A','grade':'wrong','mode':mode}))
        status,data=self.request('/v1/sync',{'events':events},token)
        self.assertEqual(status,200)
        self.assertEqual([attempt['mode'] for attempt in data['attempts']],
                         ['speed','speed-review'])

    def test_bad_bank(self):
        bank=json.loads(server.BANK.read_text())
        bank['questions'][0]['answer']='Z'
        self.assertTrue(validate(bank))
        bank=json.loads(server.BANK.read_text())
        bank['questions'].append(copy.deepcopy(bank['questions'][0]))
        self.assertTrue(validate(bank))

if __name__=='__main__':unittest.main()
