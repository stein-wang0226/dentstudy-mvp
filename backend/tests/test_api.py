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
        server.SUBMISSIONS=Path(cls.temp.name)/'question-bank-submissions'
        server.ADMIN_EMAIL='author@test.local'
        server.initialize()
        cls.author_password='testing-pass-123'
        cls.author_id='author-test-user'
        salt=server.secrets.token_hex(16)
        with server.connect() as db:
            db.execute('INSERT INTO users VALUES(?,?,?,?)',
                       (cls.author_id,'author@test.local',salt,
                        server.password_hash(cls.author_password,salt)))
            db.execute('''INSERT INTO profiles(user_id,nickname,avatar,university,updated_at)
                       VALUES(?,?,?,?,?)''',
                       (cls.author_id,'齿间同学','book','',
                        '2026-01-01T00:00:00Z'))
            db.commit()
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

    def author(self):
        status,result=self.request('/v1/auth/login',
                                   {'email':'author@test.local',
                                    'password':self.author_password})
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

    def test_open_practice_fifth_option_sync_and_comments(self):
        token = self.register('open-practice')
        q = next(q for q in server.questions()
                 if q['id'].startswith('cmb-train-') and q['answer'] == 'E')
        event = dict(id='cmb-review-test-1234567890', at='2026-01-01T04:00:00Z',
                     questionId=q['id'], kind='review',
                     value={'answer': 'E', 'grade': 'mastered', 'mode': 'practice'})
        status, data = self.request('/v1/sync', {'events': [event]}, token)
        self.assertEqual(status, 200)
        self.assertEqual(data['attempts'][0]['grade'], 'mastered')
        self.assertEqual(self.request(f"/v1/questions/{q['id']}/comments",
                                     {'body': '测试新题目评论'}, token)[0], 200)

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

    def test_question_bank_submission_is_private_and_author_visible(self):
        contributor=self.register('contributor')
        bank=json.loads(server.BANK.read_text())
        bank['questions']=[bank['questions'][0]]
        payload={'filename':'牙周整理.json','content':json.dumps(bank,ensure_ascii=False)}
        status,result=self.request('/v1/question-bank-submissions',payload,contributor)
        self.assertEqual(status,200)
        self.assertFalse(result['duplicate'])
        submission=result['submission']
        self.assertTrue((server.SUBMISSIONS/(submission['id']+'.json')).is_file())
        status,own=self.request('/v1/question-bank-submissions',token=contributor)
        self.assertEqual(status,200)
        self.assertFalse(own['isAdmin'])
        self.assertNotIn('email',own['submissions'][0])
        duplicate=self.request('/v1/question-bank-submissions',payload,contributor)[1]
        self.assertTrue(duplicate['duplicate'])
        author=self.author()
        status,inbox=self.request('/v1/question-bank-submissions',token=author)
        self.assertEqual(status,200)
        self.assertTrue(inbox['isAdmin'])
        self.assertEqual(inbox['submissions'][0]['email'],'contributor@test.local')
        download_path='/v1/admin/question-bank-submissions/'+submission['id']
        status,download=self.request(download_path,token=author)
        self.assertEqual(status,200)
        self.assertEqual(download['filename'],'牙周整理.json')
        self.assertEqual(json.loads(download['content']),bank)
        self.assertEqual(self.request(download_path,token=contributor)[0],401)
        self.assertEqual(self.request('/v1/question-bank-submissions',
                                      {'filename':'bad.json','content':'{}'},contributor)[0],400)

    def test_profile_comments_and_author_user_directory(self):
        learner=self.register('profile-learner')
        status,profile=self.request('/v1/profile',token=learner)
        self.assertEqual(status,200)
        self.assertEqual(profile['nickname'],'齿间同学')
        status,profile=self.request('/v1/profile',{
            'nickname':'小齿同学','avatar':'tooth','university':'齿间大学'},learner)
        self.assertEqual(status,200)
        self.assertEqual(profile['university'],'齿间大学')
        self.assertEqual(self.request('/v1/questions/demo-001/comments')[1]['comments'],[])
        status,result=self.request('/v1/questions/demo-001/comments',
                                   {'body':'这题的解析很清楚。'},learner)
        self.assertEqual(status,200)
        self.assertEqual(result['comment']['nickname'],'小齿同学')
        self.assertEqual(result['comment']['university'],'齿间大学')
        self.assertNotIn('email',result['comment'])
        comments=self.request('/v1/questions/demo-001/comments')[1]['comments']
        self.assertEqual(comments[0]['body'],'这题的解析很清楚。')
        self.assertEqual(self.request('/v1/questions/demo-001/comments',
                                      {'body':'未登录评论'})[0],401)
        author=self.author()
        status,directory=self.request('/v1/admin/users',token=author)
        self.assertEqual(status,200)
        listed=next(user for user in directory['users']
                    if user['email']=='profile-learner@test.local')
        self.assertEqual(directory['totalCount'], len(directory['users']))
        self.assertEqual(listed['nickname'],'小齿同学')
        self.assertEqual(listed['university'],'齿间大学')
        self.assertEqual(self.request('/v1/admin/users',token=learner)[0],401)

    def test_comment_votes_replies_and_participant_counts(self):
        first=self.register('discussion-first')
        second=self.register('discussion-second')
        question_id=server.questions()[1]['id']
        path=f'/v1/questions/{question_id}/comments'
        status,posted=self.request(path,{'body':'讨论主评论'},first)
        self.assertEqual(status,200)
        comment_id=posted['comment']['id']
        vote=f'/v1/comments/{comment_id}/vote'
        self.assertEqual(self.request(vote,{'value':1})[0],401)
        for _ in range(2):
            self.assertEqual(self.request(vote,{'value':1},first)[1],
                             {'likes':1,'dislikes':0,'myVote':1})
        self.assertEqual(self.request(vote,{'value':-1},first)[1],
                         {'likes':0,'dislikes':1,'myVote':-1})
        self.assertEqual(self.request(vote,{'value':1},second)[1]['likes'],1)
        self.assertEqual(self.request(vote,{'value':0},first)[1]['dislikes'],0)
        self.assertEqual(self.request(vote,{'value':True},first)[0],400)
        status,reply=self.request(path,{'body':'回复讨论','parentId':comment_id},second)
        self.assertEqual(status,200)
        listing=self.request(path,token=second)[1]
        self.assertEqual(listing['participantCount'],2)
        self.assertEqual(listing['totalCount'],2)
        self.assertEqual(listing['comments'][0]['myVote'],1)
        self.assertEqual(listing['comments'][1]['parentId'],comment_id)
        other_path=f"/v1/questions/{server.questions()[2]['id']}/comments"
        self.assertEqual(self.request(other_path,{'body':'跨题回复','parentId':comment_id},first)[0],400)
        self.assertNotIn('email',listing['comments'][0])
        server.initialize()  # Idempotent migration preserves comments and votes.
        self.assertEqual(self.request(path)[1]['participantCount'],2)

    def test_uploaded_avatar_validation(self):
        token=self.register('avatar-upload')
        image='data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aWQ0AAAAASUVORK5CYII='
        payload={'nickname':'头像同学','avatar':image,'university':''}
        self.assertEqual(self.request('/v1/profile',payload,token)[0],200)
        self.assertEqual(self.request('/v1/profile',token=token)[1]['avatar'],image)
        self.assertEqual(self.request('/v1/profile',{**payload,'avatar':'data:image/png;base64,invalid'},token)[0],400)
        self.assertEqual(self.request('/v1/profile',{**payload,'avatar':'https://example.com/avatar.png'},token)[0],400)

    def test_comment_deletion_ownership_replies_and_author_audit(self):
        owner=self.register('delete-owner')
        other=self.register('delete-other')
        question=server.questions()[3]
        path=f"/v1/questions/{question['id']}/comments"
        first=self.request(path,{'body':'这是可删除的评论'},owner)[1]['comment']
        reply=self.request(path,{'body':'保留他人的回复','parentId':first['id']},other)[1]['comment']
        listing=self.request(path,token=owner)[1]
        self.assertTrue(listing['comments'][0]['canDelete'])
        self.assertFalse(listing['comments'][1]['canDelete'])
        endpoint=f"/v1/comments/{first['id']}/delete"
        self.assertEqual(self.request(endpoint,{})[0],401)
        self.assertEqual(self.request(endpoint,{},other)[0],401)
        author=self.author()
        self.assertEqual(self.request(endpoint,{},author)[0],401)
        self.assertEqual(self.request('/v1/admin/comments',token=other)[0],401)
        audit=self.request('/v1/admin/comments',token=author)[1]
        record=next(item for item in audit['comments'] if item['id']==first['id'])
        self.assertEqual(record['email'],'delete-owner@test.local')
        self.assertEqual(record['questionId'],question['id'])
        self.assertEqual(record['stem'],question['stem'])
        self.assertEqual(self.request(endpoint,{},owner)[0],200)
        self.assertEqual(self.request(endpoint,{},owner)[0],200)
        listing=self.request(path,token=owner)[1]
        self.assertEqual(listing['participantCount'],1)
        self.assertEqual(listing['totalCount'],1)
        self.assertEqual(listing['comments'][0]['body'],'')
        self.assertIsNotNone(listing['comments'][0]['deletedAt'])
        self.assertFalse(listing['comments'][0]['canDelete'])
        self.assertEqual(listing['comments'][1]['body'],'保留他人的回复')
        self.assertEqual(self.request(f"/v1/comments/{first['id']}/vote",{'value':1},other)[0],400)
        self.assertEqual(self.request(path,{'body':'不能回复已删除内容','parentId':first['id']},owner)[0],400)
        audit=self.request('/v1/admin/comments',token=author)[1]
        self.assertNotIn(first['id'],[item['id'] for item in audit['comments']])
        self.assertIn(reply['id'],[item['id'] for item in audit['comments']])
        server.initialize()
        with server.connect() as db:
            self.assertEqual(db.execute('SELECT body FROM question_comments WHERE id=?',(first['id'],)).fetchone()[0],'')

if __name__=='__main__':unittest.main()
