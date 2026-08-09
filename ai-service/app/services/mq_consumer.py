"""RabbitMQ consumer for asynchronous AI jobs (screening analysis, etc.)."""
import threading

import pika

from app.config import settings
from app.logging import get_logger

log = get_logger(__name__)


def _connection_params() -> pika.ConnectionParameters:
    return pika.ConnectionParameters(
        host=settings.rabbitmq_host,
        port=settings.rabbitmq_port,
        credentials=pika.PlainCredentials(settings.rabbitmq_username, settings.rabbitmq_password),
    )


def _on_message(ch, method, properties, body):  # noqa: ANN001
    try:
        log.info("task_received", routing_key=method.routing_key)
        # TODO: decode JSON, route to AI router when job types are defined.
        ch.basic_ack(delivery_tag=method.delivery_tag)
    except Exception:  # noqa: BLE001
        log.exception("task_failed")
        ch.basic_nack(delivery_tag=method.delivery_tag, requeue=True)


def _consume_loop() -> None:
    try:
        connection = pika.BlockingConnection(_connection_params())
        channel = connection.channel()
        channel.queue_declare(queue=settings.ai_tasks_queue, durable=True)
        channel.basic_qos(prefetch_count=1)
        channel.basic_consume(settings.ai_tasks_queue, on_message_callback=_on_message)
        log.info("consumer_started", queue=settings.ai_tasks_queue)
        channel.start_consuming()
    except Exception:  # noqa: BLE001
        log.exception("consumer_connection_failed", retrying=True)
    finally:
        try:
            connection.close()
        except NameError:
            pass


def start_consumer() -> None:
    """Launch the background consumer thread (non-blocking, daemon)."""
    thread = threading.Thread(target=_consume_loop, daemon=True, name="mq-consumer")
    thread.start()