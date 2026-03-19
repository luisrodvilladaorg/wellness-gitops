--
-- PostgreSQL database dump
--

\restrict OBVeOxQnAfRaZD7Snnd4WmIBfjai9s9gqFfb8CVMm4H3hO0x9kLmbJzhhLxhL5G

-- Dumped from database version 16.13
-- Dumped by pg_dump version 16.13

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: entries; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.entries (
    id integer NOT NULL,
    title text NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT now()
);


ALTER TABLE public.entries OWNER TO postgres;

--
-- Name: entries_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.entries_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.entries_id_seq OWNER TO postgres;

--
-- Name: entries_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: postgres
--

ALTER SEQUENCE public.entries_id_seq OWNED BY public.entries.id;


--
-- Name: entries id; Type: DEFAULT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entries ALTER COLUMN id SET DEFAULT nextval('public.entries_id_seq'::regclass);


--
-- Data for Name: entries; Type: TABLE DATA; Schema: public; Owner: postgres
--

COPY public.entries (id, title, description, created_at) FROM stdin;
1	First entry	Initial test entry	2026-03-02 16:52:52.399391
2	Docker ready	Database initialized via init.sql	2026-03-02 16:52:52.399391
3	Ejemplo en Español	Este es un ejemplo en Castellano	2026-03-02 16:52:52.399391
4	día 02/03	HEmos instalado K3s y no K3d que por lo visto va mucho mejor	2026-03-02 18:11:35.640255
5	day 04	Made blue-green laboratory\nMade Canary	2026-03-04 17:21:34.070581
6	día 7	Hemos instalado nginx-ingress-controller y eliminado nginx-server ya que es redundante tener ambos	2026-03-07 08:18:42.368378
7	day 9	Fix cluster, backend pod, it was, NodePort now is ClusterIP	2026-03-09 09:41:47.911277
8	dia 10	Todo en ingles, es mejor, organización del readme, message for Recruiter, pending CICD doesn't work	2026-03-10 17:40:06.985422
9	day 11	Confirm persistent volume to database, working with STS no with deployments are more common\nmantein the same name, even if I delete it	2026-03-11 17:10:11.562125
10	day 13	Proof all about deploy complete in stage of the image\nStep by ste, these is a real situation	2026-03-13 19:11:44.022663
11	day 17	We installed ArgoCD, we can do many things speccially when we made push	2026-03-17 19:27:47.191175
12	logs del ingress nginx	kubectl logs -n ingress-nginx -f pod	2026-03-17 19:36:52.255891
\.


--
-- Name: entries_id_seq; Type: SEQUENCE SET; Schema: public; Owner: postgres
--

SELECT pg_catalog.setval('public.entries_id_seq', 12, true);


--
-- Name: entries entries_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.entries
    ADD CONSTRAINT entries_pkey PRIMARY KEY (id);


--
-- PostgreSQL database dump complete
--

\unrestrict OBVeOxQnAfRaZD7Snnd4WmIBfjai9s9gqFfb8CVMm4H3hO0x9kLmbJzhhLxhL5G

