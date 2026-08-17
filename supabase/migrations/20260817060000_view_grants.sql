select occurred_at, actor_email, action, table_name, record_ref
from audit.log
order by occurred_at desc
limit 3;