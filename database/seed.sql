INSERT INTO clubs (id, name, slug, plan, status)
VALUES ('club_demo', 'Demo Pickleball Club', 'demo', 'starter', 'active');

INSERT INTO users (id, email, name)
VALUES ('user_owner', 'coachjohnpickleball@gmail.com', 'John Mergulhao');

INSERT INTO club_users (club_id, user_id, role)
VALUES ('club_demo', 'user_owner', 'owner');
